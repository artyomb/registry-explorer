require 'zlib'
require 'archive-tar-minitar'
require 'time'
require 'json'
require_relative 'time_measurer'
require_relative 'Node'
require_relative 'caches_manager'

$base_path = (ENV['DBG'].nil? ? "/var/lib/registry" : Dir.pwd + '/../temp') + "/docker/registry/v2"

def blob_content(sha256)
  CachesManager.get_json_cache(sha256)[:content]
end

def blob_size(sha256)
  CachesManager.get_blob_size_cache(sha256)[:size]
end

def extract_tar_gz_structure(tar_gz_sha256)
  file_path = $base_path + "/blobs/sha256/#{tar_gz_sha256[0..1]}/#{tar_gz_sha256}/data"
  structure = { size: 0, is_dir: true }
  Zlib::GzipReader.open(file_path) do |gz|
    Archive::Tar::Minitar::Reader.open(gz) do |tar|
      tar.each_entry do |entry|
        # puts "#{entry.directory? ? 'DIRECTORY ' : 'FILE'} #{entry.size} #{entry.name}"
        parts = entry.prefix.split('/') + entry.name.split('/')
        current_level = structure
        parts.each_with_index do |part, index|
          if index == parts.length - 1 # Last part is a file or directory
            if !(entry.directory?)
              entry_size = entry.size
              current_level[part] = { size: entry_size, is_dir: false }
              tmp = structure

              parts.each_with_index do |tmp_part, id|
                tmp[:size] += entry_size unless id == 0
                tmp = tmp[tmp_part]
              end
            else
              current_level[part] = { size: 0 , is_dir: true} # Mark of Directory
            end
          else # Intermediate part is a directory
            current_level[part] ||= { size: 0, is_dir: true }
            current_level = current_level[part]
          end
        end
        structure[:size] += entry.size unless entry.directory?
      end
    end
  end
  structure
end

def extract_images(images=Set.new, unique_blobs_sizes=nil)
  path_to_repositories = $base_path + "/repositories"
  images_path_list = nil
  # TimeMeasurer.measure(:extract_images_paths) do
    images_path_list = Dir.glob("#{path_to_repositories}/**/*")
                          &.select do |f|
      File.directory?(f) &&
        Dir.exist?(File.join(f, "_layers")) &&
        Dir.exist?(File.join(f, "_manifests")) &&
        Dir.exist?(File.join(f, "_uploads"))
    end
  # end
  # TimeMeasurer.measure(:extract_images_after_paths_time) do
  images_path_list.each do |image_path|
    subfolders = image_path.split('/')
    image_name = "/" + subfolders[subfolders.find_index('repositories') + 1..].join('/')
    current_img = { name: image_name, tags: Set.new, total_size: -1, required_blobs: Set.new, problem_blobs: Set.new }
    images.add current_img
    Dir.glob(image_path + "/_manifests/tags/*").select { |f| File.directory?(f) }.each do |tag_path|
      extract_tag_with_image(tag_path, $base_path, image_name, current_img, unique_blobs_sizes)
    end


    current_img[:tags].each do |tag|
      current_img[:required_blobs].merge(tag[:required_blobs])
    end
    full_size_of_img = 0
    current_img[:required_blobs].each do |blob|
      begin
        current_blob_size = blob_size(blob)
        if current_blob_size == -1
          current_img[:problem_blobs].add(blob)
          raise Exception.new("Blob #{blob} not founded")
        end
        full_size_of_img += current_blob_size
      rescue Exception => e
        puts("Error: #{e.message}")
      end
    end
    current_img[:total_size] = full_size_of_img
  end
  # end
  images
end

def extract_tag_with_image(tag_path, base_path, image_name, current_img, unique_blobs_sizes=nil)
  current_tag = { name: tag_path.split('/').last, index_Nodes: [], current_index_sha256: File.read(tag_path + "/current/link").split(':').last, required_blobs: Set.new, size: -1, problem_blobs: Set.new }
  current_img[:tags].add current_tag
  indexes_paths = Dir.glob(tag_path + "/index/sha256/*")
  extract_index(current_tag[:current_index_sha256], base_path, current_tag, unique_blobs_sizes)
  indexes_paths.each do |index_path|
    index_sha256 = index_path.split('/').last
    next if index_sha256 == current_tag[:current_index_sha256]
    extract_index(index_sha256, base_path, current_tag, unique_blobs_sizes)
  end
  calculate_tag_size(current_tag)
  current_tag
end

def extract_tag_without_image(tag_path, base_path, unique_blobs_sizes=nil)
  current_tag = { name: tag_path.split('/').last, index_Nodes: [], current_index_sha256: nil, created_at: nil, required_blobs: Set.new, size: -1, problem_blobs: Set.new }
  begin
    current_tag[:current_index_sha256] = File.read(tag_path + "/current/link").split(':').last
  rescue Exception => e
    puts("Error: #{e.message}")
    return current_tag
  end
  indexes_paths = Dir.glob(tag_path + "/index/sha256/*")
  extract_index(current_tag[:current_index_sha256], base_path, current_tag, unique_blobs_sizes)
  indexes_paths.each do |index_path|
    index_sha256 = index_path.split('/').last
    next if index_sha256 == current_tag[:current_index_sha256]
    extract_index(index_sha256, base_path, current_tag, unique_blobs_sizes)
  end
  calculate_tag_size(current_tag)
  current_tag
end

def extract_index(index_sha256, base_path, current_tag, unique_blobs_sizes = nil)
  outer_index_path = base_path + "/blobs/sha256/#{index_sha256[0..1]}/#{index_sha256}/data"
  index_content = JSON.parse(File.read(outer_index_path))
  current_Node_link = { path: ["Image"], node: Node.new(index_content["mediaType"], index_sha256, index_content[:size], nil, unique_blobs_sizes), parent_sha256: index_sha256 }
  current_tag[:index_Nodes] << current_Node_link
  current_Node_link[:node].set_created_at(extract_index_created_at(index_sha256))
  current_tag[:required_blobs].merge(current_Node_link[:node].get_included_blobs)
  current_tag[:problem_blobs].merge(current_Node_link[:node].get_problem_blobs)
end

def define_create_time(sha256)
  begin
    file = File.join($base_path + "/blobs/sha256/#{sha256[0..1]}/#{sha256}/data")
    Time.at(File.ctime(file))
  rescue Exception => e
    puts "Error: #{e}"
    return nil
  end
  nil
end

def extract_file_content_from_archive_by_path(blob_sha256, file_path)
  blob_path = $base_path + "/blobs/sha256/#{blob_sha256[0..1]}/#{blob_sha256}/data"
  result = "File not found"
  founded = false
  Zlib::GzipReader.open(blob_path) do |gz|
    Archive::Tar::Minitar::Reader.open(gz) do |tar|
      tar.each_entry do |entry|
        entry_path = (entry.prefix.split('/') + entry.name.split('/')).join('/')
        if !founded && entry_path == file_path
          content = entry.read
          result =  content.force_encoding('UTF-8').encode('UTF-8', invalid: :replace, undef: :replace, replace: '?') rescue "Couldn't read content in file"
          break
        end
      end
    end
  end
  result
end

def represent_size(bytes)
  # bytes.to_s.gsub(/(\d)(?=(\d{3})+(?!\d))/, '\\1,')
  units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB']
  return '0 B' if bytes == 0

  exp = (Math.log(bytes) / Math.log(1024)).to_i
  exp = units.size - 1 if exp > units.size - 1
  size = bytes.to_f / (1024 ** exp)

  format('%.2f %s', size, units[exp])
end

def calculate_tag_size(current_tag)
  size_of_tag = 0
  current_tag[:required_blobs].each do |blob|
    begin
      current_blob_size = blob_size(blob)
      if current_blob_size == -1
        current_tag[:problem_blobs].add(blob)
        raise Exception.new("Blob #{blob} not founded")
      end
      size_of_tag += current_blob_size
    rescue Exception => e
      puts("Error: #{e.message}")
    end
  end
  current_tag[:size] = size_of_tag
  size_of_tag
end

def extract_index_created_at(sha256)
  begin
    index_json = blob_content(sha256)
    man_sha256 = index_json[:manifests] # TODO: HERE IS PROBLEM
                   &.select { |mf| !mf[:platform][:os].nil? && mf[:platform][:os] != 'unknown'}
                   .map { |mf| mf[:digest].split(':').last }
                   .first
    manifest_json = blob_content(man_sha256)
    date_sha256 = manifest_json[:config][:digest].split(':').last
    date = blob_content(date_sha256)[:created]
  rescue Exception => e
    puts "Error: #{e}"
    date =  nil
  end
  date
end

def get_referring_image_entries(blob_sha256)
  images = Set.new
  extract_images(images)
  result_list = []
  images&.select { |image| image[:required_blobs].include?(blob_sha256) }.each do |image|
    image[:tags]&.select{ |tag| tag[:required_blobs].include?(blob_sha256)}.each do |tag|
      tag[:index_Nodes].map{|node_link| node_link[:node]}&.select{|cn| cn.get_included_blobs.include?(blob_sha256)}.each do |index_node|
        result_list << { image_name: image[:name], tag_name: tag[:name], index_node: index_node }
      end
    end
  end
  result_list
end

def transform_datetime(datetime_str)
  begin
    # Parse the datetime string into a Time object
    time_obj = Time.parse(datetime_str)
    # Format the Time object into the desired format
    time_obj.strftime('%Y-%m-%d %H:%M:%S')
  rescue Exception => e
    puts "Error: #{e}"
    '-'
  end
end


def find_node_by_sha256_in_hierarchy(required_sha256, current_node)
  if current_node.sha256 == required_sha256
    return current_node
  elsif current_node.links.nil? || current_node.links.empty?
    return nil
  else
    return current_node.links.map{ |lnk| find_node_by_sha256_in_hierarchy(required_sha256, lnk[:node]) }&.select{ |result| result != nil }.first
  end
end
# def check_flattened(fl)
#   puts "Checking flattened is nil?: #{fl.nil?}"
#   fl
# end