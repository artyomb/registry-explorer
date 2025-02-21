class CachesManager
  @@cache_dict = { json_blobs: {}, blobs_sizes: {} }

  def self.get_json_cache(sha256)
    # TimeMeasurer.measure(:reading_jsons) do
    if !@@cache_dict[:json_blobs].key?sha256
      content = JSON.parse(File.read($base_path + "/blobs/sha256/#{sha256[0..1]}/#{sha256}/data"), symbolize_names: true)
      @@cache_dict[:json_blobs][sha256] ||= { content: content, load_time: Time.now }
    end
    @@cache_dict[:json_blobs][sha256]
    # end
  end

  def self.get_blob_size_cache(sha256)
    # TimeMeasurer.measure(:blob_size_time) do
    begin
      @@cache_dict[:blobs_sizes][sha256] ||= { size: File.size($base_path + "/blobs/sha256/#{sha256[0..1]}/#{sha256}/data"), load_time: Time.now }
      @@cache_dict[:blobs_sizes][sha256]
    rescue Exception => e
      puts "Error: #{e}"
      { size: -1, load_time: Time.now }
    end
    # end
  end
end