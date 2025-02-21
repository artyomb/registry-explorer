class CachesManager
  @@cache_dict = { json_blobs: {} }
  def self.get_json_cache(sha256)
    @@cache_dict[:json_blobs][sha256] ||= { content: JSON.parse(blob_content(sha256), symbolize_names: true), load_time: Time.now }
    @@cache_dict[:json_blobs][sha256]
  end
end