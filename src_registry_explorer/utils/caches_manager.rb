class CachesManager
  @@cache_dict = { json_blobs: {}, blobs_sizes: {} }

  def self.get_json_cache(sha256)
    @@cache_dict[:json_blobs][sha256] ||= { content: JSON.parse(blob_content(sha256), symbolize_names: true), load_time: Time.now }
    @@cache_dict[:json_blobs][sha256]
  end

  def self.get_blob_size_cache(sha256)
    begin
      @@cache_dict[:blobs_sizes][sha256] ||= { size: File.size($base_path + "/blobs/sha256/#{sha256[0..1]}/#{sha256}/data"), load_time: Time.now }
      @@cache_dict[:blobs_sizes][sha256]
    rescue Exception => e
      puts "Error: #{e}"
      { size: -1, load_time: Time.now }
    end
  end
end