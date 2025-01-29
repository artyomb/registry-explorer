$base_path = (ENV['DBG'].nil? ? "/var/lib/registry" : Dir.pwd + '/../docker/data') + "/docker/registry/v2"

def blob_content(sha256)
  File.read $base_path + "/blobs/sha256/#{sha256[0..1]}/data/#{sha256}"
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
    return unless n.is_a? Hash
    n.each do |key, value|
      next unless value.is_a? Hash

      add_link(path + [key], value) if value.key? :digest
      find_links path + [key], value
    end
  end

  def add_link(path, value)
    sha256 = value.is_a?(Hash) ? values[:digest][:sha256] : values[:digest][/sha256:(.*)/,1]
    @links << { path:, node: Node.new(value[:mediaType], sha256, value[:node_size]) }
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