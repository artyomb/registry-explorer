require_relative 'file_utils'
class CachesManager

  @@latest_update_time = nil
  @@cache_dict = { json_contents: { latest_update: Time.now, values: {} },
                   sizes: { latest_update: Time.now, values: {} },
                   nodes: { latest_update: Time.now, values: {} },
                   indexes_sha256: { latest_update: Time.now, values: {} },
                   repo_sizes: { latest_update: Time.now, values: {} },
                   build_metadata: { latest_update: Time.now, values: {} }
  }
  @@cache_dict_with_attest = { json_contents: { latest_update: Time.now, values: {} },
                               sizes: { latest_update: Time.now, values: {} },
                               nodes: { latest_update: Time.now, values: {} },
                               indexes_sha256: { latest_update: Time.now, values: {} },
                               repo_sizes: { latest_update: Time.now, values: {} },
                               build_metadata: { latest_update: Time.now, values: {} }
  }

  @@cache_dicts = [@@cache_dict, @@cache_dict_with_attest]


  @@cache_refresh_interval = 60 * 5 # seconds between each refresh
  @@refreshing_in_progress_no_attest = false
  @@refreshing_in_progress_with_attest = false
  def self.json_blob_content(sha256)
    # Version with cache
    TimeMeasurer.measure(:getting_jsons) do
      @@cache_dict[:json_contents][:values][sha256] ||= begin
        cont = File.read($base_path + "/blobs/sha256/#{sha256[0..1]}/#{sha256}/data")
        JSON.parse(cont, symbolize_names: true)
      end
    end

    # Version without cache
    # TimeMeasurer.measure(:reading_jsons) do
    #   begin
    #     JSON.parse(File.read($base_path + "/blobs/sha256/#{sha256[0..1]}/#{sha256}/data"), symbolize_names: true)
    #   rescue Exception => e
    #     raise "Error in json parsing: #{e}"
    #   end
    # end
  end

  def self.blob_size(sha256)
    TimeMeasurer.measure(:blob_size_time) do
      if RegistryExplorerFront.get_session.nil? || RegistryExplorerFront.get_session[:attestations_exploring]
        @@cache_dict_with_attest[:sizes][:values][sha256] ||= File.size($base_path + "/blobs/sha256/#{sha256[0..1]}/#{sha256}/data")
      else
        @@cache_dict[:sizes][:values][sha256] ||= File.size($base_path + "/blobs/sha256/#{sha256[0..1]}/#{sha256}/data")
      end
    rescue Exception => e
      puts "Error in size defining: #{e}"
      -1
    end
  end

  # def self.find_node(sha256)
  def self.get_node(type, sha256, node_size = nil)
    if !self.is_refreshing_in_progress?
      if RegistryExplorerFront.get_session.nil? || RegistryExplorerFront.get_session[:attestations_exploring]
        @@cache_dict_with_attest[:nodes][:values][sha256] ||= Node.new(type, sha256, node_size)
      else
        @@cache_dict[:nodes][:values][sha256] ||= Node.new(type, sha256, node_size)
      end
    else
      if self.is_refreshing_in_progress_no_attest?
        @@cache_dict[:nodes][:values][sha256] ||= Node.new(type, sha256, node_size)
      else
        @@cache_dict_with_attest[:nodes][:values][sha256] ||= Node.new(type, sha256, node_size)
      end
    end
  end

  def self.find_node(sha256)
    if !self.is_refreshing_in_progress?
      if RegistryExplorerFront.get_session.nil? || RegistryExplorerFront.get_session[:attestations_exploring]
        @@cache_dict_with_attest[:nodes][:values][sha256]
      else
        @@cache_dict[:nodes][:values][sha256]
      end
    else
      if self.is_refreshing_in_progress_no_attest?
        @@cache_dict[:nodes][:values][sha256]
      else
        @@cache_dict_with_attest[:nodes][:values][sha256]
      end
    end
  end

  def self.get_index_sha256(path_to_index)
    TimeMeasurer.measure(:reading_index_sha256) do
      # @@cache_dict[:indexes_sha256][:values][path_to_index] ||= File.read(path_to_index).split(':').last
      File.read(path_to_index).split(':').last
    end
  end

  def self.get_repo_size(repo_path, blobs)
    TimeMeasurer.measure(:repo_size_time) do
      if RegistryExplorerFront.get_session.nil? || RegistryExplorerFront.get_session[:attestations_exploring]
        @@cache_dict_with_attest[:repo_sizes][:values][repo_path] ||= calculate_blobs_size blobs
      else
        @@cache_dict[:repo_sizes][:values][repo_path] ||= calculate_blobs_size blobs
      end
    end
  end

  def self.build_metadata(sha256_of_node)
    cache_refreshing_lambda = lambda do |dict|
      dict[:build_metadata][:values][sha256_of_node] ||=
        begin
          head_node = CachesManager.find_node(sha256_of_node)
          return nil if head_node.nil?
          tmp = head_node
          effective_size = head_node.get_effective_size

          if head_node.node_type =~ /index/
            head_node = head_node.links.select do |link|
              link[:node].node_type =~ /manifest/ && !(
                link[:node].links.any? do |lnk|
                  lnk[:node].links.any? do |l|
                    l[:node].node_type =~ /toto/ && l[:node].node_type =~ /json/
                  end
                end
              )
            end.first[:node]
          end
          raise "No manifest found" unless head_node

          config_node_link = head_node.links.select { |link| (link[:node].node_type =~ /config/ && link[:node].node_type =~ /json/) || link[:node].node_type == 'application/vnd.docker.container.image.v1+json' }.first
          raise "No config found" unless config_node_link

          configuration = CachesManager.json_blob_content(config_node_link[:node].sha256)
          tmp.set_created_at configuration[:created] unless tmp.created_at

          result_hash = {
            created_at: configuration[:created],
            os: configuration[:os],
            architecture: configuration[:architecture],
            size: effective_size,
            environment: configuration[:config][:Env],
            labels: configuration[:config][:Labels],
            entrypoint: configuration[:config][:Entrypoint],
            cmd: configuration[:config][:Cmd]
          }

          gitlab_key_condition = lambda { |key| key =~ /GITLAB/ }
          github_key_condition = lambda { |key| key =~ /GITHUB/ }

          env_hash = configuration[:config][:Env].map {|env_var| env_var.split('=')}.to_h { |key, value| [key.to_sym, value] }
          if env_hash.keys.any?(&gitlab_key_condition)
            TimeMeasurer.measure(:extracting_gitlab_ci_cd_env) do
              result_hash[:gitlab_ci_cd_env] = env_hash.select{ |k, v| gitlab_key_condition[k] }
            end
          elsif env_hash.keys.any?(&github_key_condition)
            TimeMeasurer.measure(:extracting_github_ci_cd_env) do
              result_hash[:github_ci_cd_env] = env_hash.select(&github_key_condition)
            end
          end
          result_hash
        rescue Exception => e
          puts "Error while building metadata for #{sha256_of_node}: #{e.message}"
          nil
        end
      end
    TimeMeasurer.measure(:build_metadata_time) do
      if !self.is_refreshing_in_progress?
        if RegistryExplorerFront.get_session.nil? || RegistryExplorerFront.get_session[:attestations_exploring]
          cache_refreshing_lambda.call(@@cache_dict_with_attest)
        else
          cache_refreshing_lambda.call(@@cache_dict)
        end
      else
        if self.is_refreshing_in_progress_no_attest?
          cache_refreshing_lambda.call(@@cache_dict)
        else
          cache_refreshing_lambda.call(@@cache_dict_with_attest)
        end
      end
    end
  end

  def self.start_auto_refresh
    Thread.new do
      self.execute_refresh_pipeline
      loop do
        if Time.now - @@latest_update_time > @@cache_refresh_interval
          self.execute_refresh_pipeline
          sleep @@cache_refresh_interval
        end
        interval = @@cache_refresh_interval - (Time.now - @@latest_update_time)
        sleep interval if interval > 0
      end
    end
  end

  def self.execute_refresh_pipeline
    if is_refreshing_in_progress?
      raise "Refreshing is already in progress"
    end
    @@latest_update_time = Time.now
    @@refreshing_in_progress_with_attest = true
    refresh_nodes_cache(@@cache_dict_with_attest)
    @@refreshing_in_progress_with_attest = false
    @@refreshing_in_progress_no_attest = true
    refresh_nodes_cache(@@cache_dict)
    @@refreshing_in_progress_no_attest = false
    @@latest_update_time = Time.now
  end



  def self.cache_dict_with_attest
    @@cache_dict_with_attest
  end

  def self.cache_dict
    @@cache_dict
  end

  def self.is_refreshing_in_progress?
    @@refreshing_in_progress_no_attest || @@refreshing_in_progress_with_attest
  end

  def self.is_refreshing_in_progress_no_attest?
    @@refreshing_in_progress_no_attest
  end

  def self.is_refreshing_in_progress_with_attest?
    @@refreshing_in_progress_with_attest
  end

  private

  def self.refresh_nodes_cache(dict)
    TimeMeasurer.start_measurement
    TimeMeasurer.measure(:refresh_cache_time) do
      puts "🔄 Refreshing cache at #{Time.now}"
      json_cashes = actualize_json_cashes(dict[:json_contents][:values])
      # sizes_caches = actualize_blobs_sizes_cashes(dict[:sizes][:values])
      dict.keys.each do |key|
        dict[key][:latest_update] = Time.now
        dict[key][:values] = {}
      end
      dict[:json_contents][:values] = json_cashes
      # dict[:sizes][:values] = sizes_caches
      tree = { children: {}, image: {}, total_images_amount: 0, required_blobs: Set.new, problem_blobs: Set.new }
      images = extract_images(Set.new)
      build_tree(images, tree)
      flat = flatten_tree(tree)
      flat.each do |node|
        node[:children_count] == 0 ? represent_size(node[:image][:total_size]) : CachesManager.get_repo_size("#{$base_path}/repositories/#{node[:name]}", node[:required_blobs])
      end
    end
    TimeMeasurer.log_measurers
    TimeMeasurer.start_measurement
    puts "Preforming extracting images after refresh"
    tree = { children: {}, image: {}, total_images_amount: 0, required_blobs: Set.new, problem_blobs: Set.new }
    images = extract_images(Set.new)
    build_tree(images, tree)
    flat = flatten_tree(tree)
    flat.each do |node|
      node[:children_count] == 0 ? represent_size(node[:image][:total_size]) : CachesManager.get_repo_size("#{$base_path}/repositories/#{node[:name]}", node[:required_blobs])
    end
    TimeMeasurer.log_measurers
  end

  def self.actualize_json_cashes(json_cashes)
    path_to_check_presence = "#{$base_path}/blobs/sha256/"
    json_cashes.reject! do |sha256_of_node, _|
      !File.exist?(File.join(path_to_check_presence, sha256_of_node[0..1], sha256_of_node, 'data'))
    end
    json_cashes
  end
  #
  # def self.actualize_blobs_sizes_cashes(sizes_dict)
  #   path_to_check_presence = "#{$base_path}/blobs/sha256/"
  #   sizes_dict.reject! do |sha256_of_node, _|
  #     !File.exist?(File.join(path_to_check_presence, sha256_of_node[0..1], sha256_of_node, 'data'))
  #   end
  #   sizes_dict
  # end
end
# 7dbb79e914894fa3f885e27b5eb19f0b30afdf2c (current index of stack-insight)
# sha256:b017f4f91e71393f966e8063623fb49a61403f75946d0415022762d1e6a68adb (manifest of stack-insight(from current index))
# {
#   "schemaVersion": 2,
#   "mediaType": "application/vnd.oci.image.index.v1+json",
#   "manifests": [
#     {
#       "mediaType": "application/vnd.oci.image.manifest.v1+json",
#       "digest": "sha256:b017f4f91e71393f966e8063623fb49a61403f75946d0415022762d1e6a68adb",
#       "size": 2007,
#       "platform": {
#         "architecture": "amd64",
#         "os": "linux"
#       }
#     },
#     {
#       "mediaType": "application/vnd.oci.image.manifest.v1+json",
#       "digest": "sha256:5b6de226858a9ecf279e67b1cb018fbd340016397fbadc83eee3e5e853e779bf",
#       "size": 567,
#       "annotations": {
#         "vnd.docker.reference.digest": "sha256:b017f4f91e71393f966e8063623fb49a61403f75946d0415022762d1e6a68adb",
#         "vnd.docker.reference.type": "attestation-manifest"
#       },
#       "platform": {
#         "architecture": "unknown",
#         "os": "unknown"
#       }
#     }
#   ]
# }