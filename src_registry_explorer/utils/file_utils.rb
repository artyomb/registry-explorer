require 'zlib'
require 'archive-tar-minitar'

$base_path = (ENV['DBG'].nil? ? "/var/lib/registry" : Dir.pwd + '/../temp') + "/docker/registry/v2"

def blob_content(sha256)
  File.read $base_path + "/blobs/sha256/#{sha256[0..1]}/#{sha256}/data"
end

def blob_size(sha256)
  begin
    File.size $base_path + "/blobs/sha256/#{sha256[0..1]}/#{sha256}/data"
  rescue Exception => e
    puts "Error: #{e}"
    -1
  end
end

def extract_tar_gz_structure(tar_gz_sha256)
  file_path = $base_path + "/blobs/sha256/#{tar_gz_sha256[0..1]}/#{tar_gz_sha256}/data"
  structure = {size: 0, is_dir: true }

  Zlib::GzipReader.open(file_path) do |gz|
    Archive::Tar::Minitar::Reader.open(gz) do |tar|
      tar.each_entry do |entry|
        # puts "#{entry.directory? ? 'DIRECTORY ' : 'FILE'} #{entry.size} #{entry.name}"
        parts = entry.name.split('/')
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


def extract_tag_with_image(tag_path, base_path, image_name, current_img, unique_blobs_sizes=nil)
  puts("Image #{image_name}")
  puts("Founded tag #{tag_path}")
  current_tag = { name: tag_path.split('/').last, index_Nodes: [], current_index_sha256: File.read(tag_path + "/current/link").split(':').last, required_blobs: Set.new, size: -1, problem_blobs: [] }
  current_img[:tags] << current_tag
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

def extract_tag_without_image(tag_path, base_path)
  current_tag = { name: tag_path.split('/').last, index_Nodes: [], current_index_sha256: nil, created_at: nil, required_blobs: Set.new, size: -1, problem_blobs: [] }
  begin
    current_tag[:current_index_sha256] = File.read(tag_path + "/current/link").split(':').last
  rescue Exception => e
    puts("Error: #{e.message}")
    return current_tag
  end
  indexes_paths = Dir.glob(tag_path + "/index/sha256/*")
  extract_index(current_tag[:current_index_sha256], base_path, current_tag)
  indexes_paths.each do |index_path|
    index_sha256 = index_path.split('/').last
    next if index_sha256 == current_tag[:current_index_sha256]
    extract_index(index_sha256, base_path, current_tag)
  end
  calculate_tag_size(current_tag)
  current_tag
end

def extract_index(index_sha256, base_path, current_tag, unique_blobs_sizes = nil)
  outer_index_path = base_path + "/blobs/sha256/#{index_sha256[0..1]}/#{index_sha256}/data"
  index_content = JSON.parse(File.read(outer_index_path))
  current_Node_link = { path: ["Image"], node: Node.new(index_content["mediaType"], index_sha256, index_content[:size], nil, unique_blobs_sizes), parent_sha256: index_sha256 }
  current_tag[:index_Nodes] << current_Node_link
  current_tag[:required_blobs].merge(current_Node_link[:node].get_included_blobs)
end

def define_create_time(sha256)
  begin
    file = File.join($base_path + "/blobs/sha256/#{sha256[0..1]}/#{sha256}/data")
    Time.at(File.ctime(file))
  rescue Exception => e
    puts "Error: #{e}"
    return nil
  end
end

def extract_file_content_from_archive_by_path(blob_sha256, file_path)
  blob_path = $base_path + "/blobs/sha256/#{blob_sha256[0..1]}/#{blob_sha256}/data"
  Zlib::GzipReader.open(blob_path) do |gz|
    Archive::Tar::Minitar::Reader.open(gz) do |tar|
      tar.each_entry do |entry|
        if entry.name == file_path

          content = entry.read
          return content.force_encoding('UTF-8').encode('UTF-8', invalid: :replace, undef: :replace, replace: '?') rescue "Couldn't read content in file"
        end
      end
    end
  end
  "File not found"
end

def represent_size(size_in_bytes)
  size_in_bytes.to_s.gsub(/(\d)(?=(\d{3})+(?!\d))/, '\\1,')
end

def calculate_tag_size(current_tag)
  size_of_tag = 0
  current_tag[:required_blobs].each do |blob|
    begin
      current_blob_size = blob_size(blob)
      if current_blob_size == -1
        current_tag[:problem_blobs] << blob
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