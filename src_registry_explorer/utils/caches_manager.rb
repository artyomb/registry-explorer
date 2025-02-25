require_relative 'file_utils'
class CachesManager
  @@cache_dict = { json_contents: { latest_update: Time.now, values: {} },
                   sizes: { latest_update: Time.now, values: {} },
                   nodes: { latest_update: Time.now, values: {} },
                   indexes_sha256: {latest_update: Time.now, values: {} },
                   repo_sizes: {latest_update: Time.now, values: {} }
  }


  @@cache_refresh_interval = 60 * 5 # seconds between each refresh
  @@refreshing_in_progress = false
  def self.json_blob_content(sha256)
    TimeMeasurer.measure(:reading_jsons) do
      if !@@refreshing_in_progress || @@refreshing_in_progress
        @@cache_dict[:json_contents][:values][sha256] ||= begin
          cont = File.read($base_path + "/blobs/sha256/#{sha256[0..1]}/#{sha256}/data")
          JSON.parse(cont, symbolize_names: true)
        end
      end
    end
  end

  def self.blob_size(sha256)
    TimeMeasurer.measure(:blob_size_time) do
      if !@@refreshing_in_progress || @@refreshing_in_progress
        @@cache_dict[:sizes][:values][sha256] ||= File.size($base_path + "/blobs/sha256/#{sha256[0..1]}/#{sha256}/data")
      end
    rescue Exception => e
      puts "Error: #{e}"
      -1
    end
  end

  # def self.find_node(sha256)
  def self.get_node(type, sha256, node_size = nil)
    if !@@refreshing_in_progress || @@refreshing_in_progress
      @@cache_dict[:nodes][:values][sha256] ||= Node.new(type, sha256, node_size)
    end
  end

  def self.get_index_sha256(path_to_index)
    TimeMeasurer.measure(:reading_index_sha256) do
      @@cache_dict[:indexes_sha256][:values][path_to_index] ||= File.read(path_to_index).split(':').last
    end
  end

  def self.get_repo_size(repo_path, blobs)
    TimeMeasurer.measure(:repo_size_time) do
      @@cache_dict[:repo_sizes][:values][repo_path] ||= calculate_blobs_size blobs
    end
  end

  def self.start_auto_refresh
    Thread.new do
      @@refreshing_in_progress = true
      refresh_nodes_cache
      @@refreshing_in_progress = false
      loop do
        sleep @@cache_refresh_interval
        @@refreshing_in_progress = true
        refresh_nodes_cache
        @@refreshing_in_progress = false
      end
    end
  end

  private

  def self.refresh_nodes_cache
    TimeMeasurer.start_measurement
    TimeMeasurer.measure(:refresh_cache_time) do
      puts "🔄 Refreshing cache at #{Time.now}"
      @@cache_dict.keys.each do |key|
        @@cache_dict[key][:latest_update] = Time.now
        @@cache_dict[key][:values] = {}
      end
      extract_images(Set.new)
    end
    TimeMeasurer.log_measurers
    TimeMeasurer.start_measurement
    puts "Preforming extracting images after refresh"
    extract_images(Set.new)
    TimeMeasurer.log_measurers
  end
end