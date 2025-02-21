class CachesManager
  @@cache_dict = { json_contents: {}, sizes: {} }

  def self.json_blob_content(sha256)
    TimeMeasurer.measure(:reading_jsons) do
      if !@@cache_dict[:json_contents].key?sha256
        content = JSON.parse(File.read($base_path + "/blobs/sha256/#{sha256[0..1]}/#{sha256}/data"), symbolize_names: true)
        @@cache_dict[:json_contents][sha256] ||= content
      end
      @@cache_dict[:json_contents][sha256]
    end
  end

  def self.blob_size(sha256)
    TimeMeasurer.measure(:blob_size_time) do
      begin
        @@cache_dict[:sizes][sha256] ||= File.size($base_path + "/blobs/sha256/#{sha256[0..1]}/#{sha256}/data")
        @@cache_dict[:sizes][sha256]
      rescue Exception => e
        puts "Error: #{e}"
        -1
      end
    end
  end
end