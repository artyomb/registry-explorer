require 'zlib'
require 'archive-tar-minitar'

$base_path = (ENV['DBG'].nil? ? "/var/lib/registry" : Dir.pwd + '/../docker/data') + "/docker/registry/v2"

def blob_content(sha256)
  File.read $base_path + "/blobs/sha256/#{sha256[0..1]}/#{sha256}/data"
end

def blob_size(sha256)
  File.size $base_path + "/blobs/sha256/#{sha256[0..1]}/#{sha256}/data"
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
              parts.each do |tmp_part|
                tmp[:size] += entry_size
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


def extract_tag_with_image(tag_path, base_path, image_name, current_img)
  puts("Image #{image_name}")
  puts("Founded tag #{tag_path}")
  current_tag = { name: tag_path.split('/').last, index_Nodes: [], current_index_sha256: File.read(tag_path + "/current/link").split(':').last }
  current_img[:tags] << current_tag
  indexes_paths = Dir.glob(tag_path + "/index/sha256/*")
  extract_index(current_tag[:current_index_sha256], base_path, current_tag)
  indexes_paths.each do |index_path|
    index_sha256 = index_path.split('/').last
    next if index_sha256 == current_tag[:current_index_sha256]
    extract_index(index_sha256, base_path, current_tag)
  end
  puts
end

def extract_tag(tag_path, base_path)
  current_tag = { name: tag_path.split('/').last, index_Nodes: [], current_index_sha256: nil, size: nil, created_at: nil }
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
  puts
  current_tag
end

def extract_index(index_sha256, base_path, current_tag)
  outer_index_path = base_path + "/blobs/sha256/#{index_sha256[0..1]}/#{index_sha256}/data"
  index_content = JSON.parse(File.read(outer_index_path))
  puts("Tag has index #{index_sha256} with content in blob: #{JSON.pretty_generate(index_content)}")
  current_Node_link = { path: ["Image"], node: Node.new(index_content["mediaType"], index_sha256, index_content[:size]), parent_sha256: index_sha256 }
  current_tag[:index_Nodes] << current_Node_link
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

class Node
  def initialize(type, sha256, node_size = nil)
    @type = type
    @sha256 = sha256
    @node_size = node_size
    @created_at = define_create_time sha256
    @links = []
    @created_at = nil
    @created_by = nil
    begin
      @actual_blob_size = blob_size(@sha256)
    rescue Exception => e
      puts "Error: #{e}"
      @actual_blob_size = -1
    end
    return unless @type.to_s =~ /json/
    find_links JSON.parse blob_content(@sha256), symbolize_names: true
  end

  def find_links(n, path = [])
    return unless (n.is_a? Hash or n.is_a? Array)
    if n.is_a? Hash
      n.each do |key, value|
        if value.is_a? Hash
          add_link(path + [key], value) if value.key? :digest
          find_links(value, path + [key])
        elsif value.is_a? Array
          find_links(value, path + [key])
        end
      end
    elsif n.is_a? Array
      n.each_with_index do |sub_hash, id|
        if sub_hash.is_a? Hash
          add_link(path + ["[#{id}]"], sub_hash) if sub_hash.key? :digest
          find_links(sub_hash, path + ["[#{id}]"])
        end
      end
    end
  end

  def add_link(path, value)
    digest_val = value[:digest]
    sha256 = digest_val.is_a?(Hash) ? digest_val[:sha256] : digest_val.split(':').last
    @links << { path:, node: Node.new(value[:mediaType], sha256, value[:size]) }
    puts("Noode #{sha256} with type #{@type} added link to node #{@links.last}")
  end

  def node_type
    @type
  end

  def sha256
    @sha256
  end

  def node_size
    @node_size
  end

  def actual_blob_size
    @actual_blob_size
  end

  def links
    @links
  end

  def created_at
    @created_at
  end

  def created_by
    @created_by
  end
end