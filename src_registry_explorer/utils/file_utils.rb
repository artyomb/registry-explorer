require 'zlib'
require 'archive-tar-minitar'
require 'time'
require 'json'
require 'find'
require_relative 'time_measurer'
require_relative 'Node'
require_relative 'caches_manager'

$base_path = (ENV['DBG'].nil? ? "/var/lib/registry" : Dir.pwd + '/../temp') + "/docker/registry/v2"
$registry_host = ENV['DBG'].nil? ? ENV['REGISTRY_HOST'] : "172.22.0.1:5000"
# In case when 'REGISTRY_HOST' in production is not set, user must get warning message about it
warn "REGISTRY_HOST is not set, features with registry API interactions are disabled" if $registry_host.nil?

$hostname = ENV['DBG'].nil? ? $registry_host.split(':').first : "localhost" unless $registry_host.nil?
$port = ENV['DBG'].nil? ? ($registry_host.include?(':') ? $registry_host.split(':').last : nil ) : "5000" unless $registry_host.nil?
$temp_dir = Dir.pwd + '/temp_registry_blobs/blobs'
$zip_time_limit = 60 * 10
$read_only_mode = ENV['DBG'].nil? ? ((!ENV['READ_ONLY_MODE'].nil? && ENV['READ_ONLY_MODE'] == 'false') ? false : true) : false

def extract_tar_gz_structure(tar_gz_sha256)
  TimeMeasurer.measure(:extracting_gz_structure) do
    temp_path = "#{$temp_dir}/#{tar_gz_sha256}"
    structure_file = "#{temp_path}/structure.json"

    # If structure already exists, load from disk
    if File.exist?(structure_file)
      return JSON.parse(File.read(structure_file), symbolize_names: true)
    end

    file_path = "#{$base_path}/blobs/sha256/#{tar_gz_sha256[0..1]}/#{tar_gz_sha256}/data"
    if !File.exist?(file_path)
      error_message = "Blob by following path not found: #{file_path}"
      raise error_message
    end
    structure = { size: 0, is_dir: true }

    # Create temp directory and extract the archive
    FileUtils.mkdir_p(temp_path)
    system("tar", "xf", file_path, "-C", temp_path)

    # Build structure by traversing the extracted files
    file_sizes = {} # Temporary hash to store file sizes
    Find.find(temp_path) do |path|
      next if path == temp_path  # Skip root directory

      relative_path = path.sub("#{temp_path}/", '')
      path_parts = relative_path.split('/')
      current_level = structure

      if File.directory?(path)
        # Ensure directory entry exists
        path_parts.each do |part|
          current_level[part] ||= { size: 0, is_dir: true }
          current_level = current_level[part]
        end
      else
        # Store file size
        size = begin
                 File.size(path)
               rescue Errno::ENOENT
                 puts "Warning: File not found while processing #{path}"
                 0
               end
        file_sizes[relative_path] = size

        # Update size for all parent directories
        path_parts.each_with_index do |part, index|
          is_last = index == path_parts.length - 1
          current_level[part] ||= { size: 0, is_dir: !is_last }
          current_level[part][:size] += size
          current_level = current_level[part] unless is_last
        end
        structure[:size] += size
      end
    end

    # Store the extracted structure on disk for fast retrieval
    File.write(structure_file, JSON.pretty_generate(structure))

    # Cleanup old directories
    cleanup_old_temp_dirs

    structure
  end
end

def cleanup_old_temp_dirs
  Dir.glob("#{$temp_dir}/*").each do |dir|
    next unless File.directory?(dir)
    next unless File.mtime(dir) < Time.now - $zip_time_limit
    FileUtils.rm_rf(dir)
  end
end

def extract_images(images=Set.new)
  images_paths = get_images_paths
  TimeMeasurer.measure(:images_paths_after) do
    images_paths.each do |image_path|
      subfolders = image_path.split('/')
      image_name = "/" + subfolders[subfolders.find_index('repositories') + 1..].join('/')
      current_img = { name: image_name, tags: Set.new, total_size: -1, required_blobs: Set.new, problem_blobs: Set.new }
      tag_paths = Dir.glob(image_path + "/_manifests/tags/*").select { |f| File.directory?(f) }
      TimeMeasurer.measure(:creating_tags) do
        tag_paths.map { |tag_path| extract_tag(tag_path) }.each do |tag|
          current_img[:tags].add(tag)
          current_img[:required_blobs].merge(tag[:required_blobs])
          current_img[:problem_blobs].merge(tag[:problem_blobs])
        end
      end
      next if current_img[:tags].empty?
      images.add current_img
      current_img[:total_size] = CachesManager.get_repo_size(image_path, current_img[:required_blobs])
    end
  end
  images
end

def extract_tag(tag_path)
  current_tag = { name: tag_path.split('/').last, index_Nodes: [], current_index_sha256: CachesManager.get_index_sha256(tag_path + "/current/link"), required_blobs: Set.new, size: -1, problem_blobs: Set.new }
  indexes_paths = Dir.glob(tag_path + "/index/sha256/*")
  current_tag[:index_Nodes] << extract_index(current_tag[:current_index_sha256])
  index_without_problems = []
  problem_indexes = []
  indexes_paths.each do |index_path|
    index_sha256 = index_path.split('/').last
    next if index_sha256 == current_tag[:current_index_sha256] || !File.exist?(tag_path + "/../../revisions/sha256/#{index_sha256}/link")
    cur_index = extract_index(index_sha256)
    if cur_index[:node].get_problem_blobs.size > 0
      problem_indexes << cur_index
    else
      index_without_problems << cur_index
    end
  end
  index_without_problems.sort_by! { _1[:node]&.created_at || '-' }.reverse!
  current_tag[:index_Nodes].append(*index_without_problems)
  current_tag[:index_Nodes].append(*problem_indexes)
  TimeMeasurer.measure(:search_tags_blobs) do
    current_tag[:index_Nodes].map do |index_node|
      current_tag[:required_blobs].merge index_node[:node].get_included_blobs
      current_tag[:problem_blobs].merge index_node[:node].get_problem_blobs
    end
  end
  current_tag[:size] = CachesManager.get_repo_size(tag_path, current_tag[:required_blobs])
  current_tag
end

def extract_index(index_sha256)
  index_node_link = { path: ['Image'], node: CachesManager.get_node(nil, index_sha256, CachesManager.blob_size(index_sha256)) }
  index_node_link[:build_info] = CachesManager.build_metadata(index_node_link[:node].sha256) unless index_node_link[:node].actual_blob_size <= 0 || index_node_link[:node].get_problem_blobs.size > 0
  index_node_link[:build_info] ||= nil
  index_node_link
end

def extract_file_content_from_archive_by_path(blob_sha256, file_path)
  if !Dir.exist?("#{$temp_dir}/#{blob_sha256}")
    source_path = "#{$base_path}/blobs/sha256/#{blob_sha256[0..1]}/#{blob_sha256}/data"
    FileUtils.mkdir_p("#{$temp_dir}/#{blob_sha256}")
    system("tar", "xf", source_path, "-C", "#{$temp_dir}/#{blob_sha256}")
  end

  full_path = "#{$temp_dir}/#{blob_sha256}/#{file_path}"
  if File.exist?(full_path)
    content = File.read(full_path)
    content.force_encoding('UTF-8').encode('UTF-8', invalid: :replace, undef: :replace, replace: '?') rescue "Couldn't read content in file"
  else
    "File not found"
  end
end

def calculate_blobs_size(blobs)
  TimeMeasurer.measure(:blobs_size_summ_calc) do
    blobs.sum do |blob|
      begin
        current_blob_size = CachesManager.blob_size(blob)
        if current_blob_size == -1
          puts("Error when blobs size calculation: Blob #{blob} not founded")
          0
        else
          current_blob_size
        end
      rescue Exception => e
        puts("Error when blobs size calculation: #{e.message}")
        0
      end
    end
  end
end

def get_images_paths
  path_to_repositories = $base_path + "/repositories"
  TimeMeasurer.measure(:images_paths_before) do
    images_paths = Set.new

    Find.find(path_to_repositories) do |path|
      next unless File.directory?(path)
      subdirs = %w[_layers _manifests _uploads]
      if subdirs.all? { |subdir| Dir.exist?(File.join(path, subdir)) }
        images_paths.add path
        Find.prune
      end
    end
    images_paths
  end
end

def get_referring_image_entries(blob_sha256)
  TimeMeasurer.measure(:referring_image_entries) do
    images = Set.new
    extract_images(images)
    result_list = []
    images&.select { |image| image[:required_blobs].include?(blob_sha256) }.each do |image|
      image[:tags]&.select{ |tag| tag[:required_blobs].include?(blob_sha256)}.each do |tag|
        tag[:index_Nodes].map{ |node_link| node_link[:node] }&.select{|cn| cn.get_included_blobs.include?(blob_sha256)}.each do |index_node|
          result_list << { image_name: image[:name], tag_name: tag[:name], index_node: index_node }
        end
      end
    end
    result_list
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

def build_tree(images, tree)
  images.each do |image|
    path_parts = image[:name].split('/')[1..] # Skip first empty element from leading '/'
    current = tree
    path_parts.each do |part|
      current[:total_images_amount] += 1
      current[:required_blobs].merge(image[:required_blobs])
      if image[:problem_blobs].size > 0
        current[:problem_blobs].merge(image[:problem_blobs])
      end
      current[:children][part] ||= { children: {}, image: {}, total_images_amount: 0, required_blobs: Set.new, problem_blobs: Set.new }
      current = current[:children][part]
    end
    current[:image] = image
    current[:problem_blobs] ||= Set.new
    current[:problem_blobs].merge(image[:problem_blobs])
  end
end

def flatten_tree(node, level = 0, pname = nil)
  result = []
  node[:children].each do |name, child|
    result << { name: [pname, name].flatten.compact.join('/'), level: level, image: child[:image], children_count: child[:total_images_amount], required_blobs: child[:required_blobs], problem_blobs: child[:problem_blobs] }
    result.concat(flatten_tree(child, level + 1, [pname, name]))
  end
  result
end


def debugging(val)
  puts "DEBUGGING: #{val}"
end
