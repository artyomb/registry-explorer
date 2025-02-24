class CachesManager
  @@cache_dict = { json_contents: {}, sizes: {}, nodes: {} }

  def self.json_blob_content(sha256)
    TimeMeasurer.measure(:reading_jsons) do
      @@cache_dict[:json_contents][sha256] ||= begin
        cont = File.read($base_path + "/blobs/sha256/#{sha256[0..1]}/#{sha256}/data")
        JSON.parse(cont, symbolize_names: true)
      end
    end
  end

  def self.blob_size(sha256)
    TimeMeasurer.measure(:blob_size_time) do
      @@cache_dict[:sizes][sha256] ||= File.size($base_path + "/blobs/sha256/#{sha256[0..1]}/#{sha256}/data")
    rescue Exception => e
      puts "Error: #{e}"
      -1
    end
  end

  # def self.find_node(sha256)
  def self.get_node(type, sha256, node_size = nil, required_blobs = nil)
    @@cache_dict[:nodes][sha256] ||= Node.new(type, sha256, node_size, required_blobs)
  end
end