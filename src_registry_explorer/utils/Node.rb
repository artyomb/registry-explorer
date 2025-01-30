$base_path = (ENV['DBG'].nil? ? "/var/lib/registry" : Dir.pwd + '/../docker/data') + "/docker/registry/v2"

def blob_content(sha256)
  File.read $base_path + "/blobs/sha256/#{sha256[0..1]}/#{sha256}/data"
end

class Node
  def initialize(type, sha256, node_size = nil)
    @type = type
    @sha256 = sha256
    @node_size = node_size
    @links = []
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
          add_link(path + ["Array_id_#{id}"], sub_hash) if sub_hash.key? :digest
          find_links(sub_hash, path + ["Array_Id_#{id}"])
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

  def links
    @links
  end
end