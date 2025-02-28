require_relative 'file_utils'
class CachesManager
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
  @@refreshing_in_progress = false
  def self.json_blob_content(sha256)
    # Version with cache
    # TimeMeasurer.measure(:reading_jsons) do
    #   if !@@refreshing_in_progress || @@refreshing_in_progress
    #     @@cache_dict[:json_contents][:values][sha256] ||= begin
    #       cont = File.read($base_path + "/blobs/sha256/#{sha256[0..1]}/#{sha256}/data")
    #       JSON.parse(cont, symbolize_names: true)
    #     end
    #   end
    # end

    # Version without cache
    TimeMeasurer.measure(:reading_jsons) do
      JSON.parse(File.read($base_path + "/blobs/sha256/#{sha256[0..1]}/#{sha256}/data"), symbolize_names: true)
    end
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
    if !@@refreshing_in_progress
      if RegistryExplorerFront.get_session.nil? || RegistryExplorerFront.get_session[:attestations_exploring]
        @@cache_dict_with_attest[:nodes][:values][sha256] ||= Node.new(type, sha256, node_size)
      else
        @@cache_dict[:nodes][:values][sha256] ||= Node.new(type, sha256, node_size)
      end
    else
      @@cache_dicts.each do |dict|
        dict[:nodes][:values][sha256] ||= Node.new(type, sha256, node_size)
      end
      return @@cache_dict_with_attest[:nodes][:values][sha256]
    end
  end

  def self.find_node(sha256, explore_attestation)
    if explore_attestation
      @@cache_dict_with_attest[:nodes][:values][sha256]
    else
      @@cache_dict[:nodes][:values][sha256]
    end
  end

  def self.get_index_sha256(path_to_index)
    TimeMeasurer.measure(:reading_index_sha256) do
      @@cache_dict[:indexes_sha256][:values][path_to_index] ||= File.read(path_to_index).split(':').last
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
    cache_refreshing_lambda = lambda do |dict, explore_attestation|
      dict[:build_metadata][:values][sha256_of_node] ||=
        begin
          head_node = CachesManager.find_node(sha256_of_node, explore_attestation)
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
        end
      end
    TimeMeasurer.measure(:build_metadata_time) do
      if @@refreshing_in_progress
        [@@cache_dict_with_attest, @@cache_dict].each_with_index { |dict, i| cache_refreshing_lambda.call(dict, i == 0) }
      else
        if RegistryExplorerFront.get_session.nil? || RegistryExplorerFront.get_session[:attestations_exploring]
          cache_refreshing_lambda.call(@@cache_dict_with_attest, true)
        else
          cache_refreshing_lambda.call(@@cache_dict, false)
        end
      end
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


  def self.cache_dict_with_attest
    @@cache_dict_with_attest
  end

  def self.cache_dict
    @@cache_dict
  end


  private

  def self.refresh_nodes_cache
    TimeMeasurer.start_measurement
    TimeMeasurer.measure(:refresh_cache_time) do
      puts "🔄 Refreshing cache at #{Time.now}"
      @@cache_dicts.each do |dict|
        dict.keys.each do |key|
          dict[key][:latest_update] = Time.now
          dict[key][:values] = {}
        end
      end
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
end