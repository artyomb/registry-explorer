require_relative '../sinatra/sinatra_server'
class Node
  @@nodes_created = 0
  @@json_nodes_created = 0
  @@not_json_nodes_created = 0
  def self.nodes_created
    @@nodes_created
  end
  def self.json_nodes_created
    @@json_nodes_created
  end
  def self.not_json_nodes_created
    @@not_json_nodes_created
  end

  def initialize(type, sha256, node_size = nil)
    @type = type
    @sha256 = sha256
    @node_size = node_size
    @problem_blobs = Set.new
    @links = []
    @created_at = nil
    @created_by = nil
    @@nodes_created += 1
    begin
      @actual_blob_size = CachesManager.blob_size(@sha256)
      if @actual_blob_size.nil? || @actual_blob_size == -1
        @problem_blobs.add(@sha256)
      end
    rescue Exception => e
      puts "Error when Node with sha256 = #{@sha256} initialization: #{e}"
      @problem_blobs.add(@sha256)
      @actual_blob_size = -1
      return
    end
    if @type.to_s =~ /zip/
      @@not_json_nodes_created+=1
      return
    end

    json_blob_content ||= begin
                            CachesManager.json_blob_content(@sha256)
                          rescue Exception => e
                            @actual_blob_size = -1
                            @problem_blobs.add(@sha256)
                            puts "Error in json blob content by sha256#{@sha256}: #{e}"
                            return
                          end
    @type ||= json_blob_content[:mediaType] # "application/vnd.oci.image.index.v1+json"

    # Check if the keys exist and delete the :materials key to avoid exploring digests with external uri
    if @type.to_s =~ /toto/ && @type.to_s =~ /json/
      if json_blob_content[:predicate] && json_blob_content[:predicate].is_a?(Hash)
        json_blob_content[:predicate].delete(:materials)
      end
    end
    find_links(json_blob_content, [])
    begin
      explore_attestations_in_session = RegistryExplorerFront.get_session.nil? || RegistryExplorerFront.get_session[:attestations_exploring]
      removing_to_to_links_condition = CachesManager.is_refreshing_in_progress_no_attest? || (!CachesManager.is_refreshing_in_progress? && !(explore_attestations_in_session))
      if removing_to_to_links_condition
        @links.each do |link|
          if link[:node].node_type.to_s =~ /json/ && link[:node].node_type.to_s =~ /toto/
            @links = []
            return
          end
        end
      end
    rescue Exception => e
      puts "Error when processing toto json: #{e}"
      return
    end
    TimeMeasurer.measure(:defining_problem_blobs) do
      @links.each do |link|
        if link[:node].actual_blob_size == -1
          @problem_blobs.add(link[:node].sha256)
        else
          @problem_blobs.merge(link[:node].get_problem_blobs)
        end
      end
    end
    @@json_nodes_created += 1
  end

  def find_links(n, path = [])
    # TimeMeasurer.measure(:finding_links_for_node) do
    return unless (n.is_a? Hash or n.is_a? Array)
    if n.is_a? Hash
      if !(n.key?(:config) && n[:config].key?(:digest) && n.key?(:layers))
        n.each do |key, value|
          if value.is_a? Hash
            add_link(path + [key], value) if value.key? :digest
            find_links(value, path + [key])
          elsif value.is_a? Array
            find_links(value, path + [key])
          end
        end
      else
        add_links_by_config(n, path)
      end
    elsif n.is_a? Array
      n.each_with_index do |sub_hash, id|
        if sub_hash.is_a? Hash
          add_link(path + ["[#{id}]"], sub_hash) if sub_hash.key? :digest
          find_links(sub_hash, path + ["[#{id}]"])
        end
      end
    end
    # end
  end

  def add_link(path, value)
    digest_val = value[:digest]
    sha256 = digest_val.is_a?(Hash) ? digest_val[:sha256] : digest_val.split(':').last
    @links << { path:, node: CachesManager.get_node(value[:mediaType], sha256, value[:size]) }
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

  def actual_blob_size
    @actual_blob_size
  end

  def links
    @links
  end

  def created_at
    @created_at
  end

  def created_by
    @created_by
  end

  def set_created_at(new_created_at)
    @created_at = new_created_at
  end

  def set_created_by(new_created_by)
    @created_by = new_created_by
  end

  def get_included_blobs
    @included_blobs ||= begin
                          included_blobs = Set.new
                          included_blobs.add(@sha256)
                          @links.each do |link|
                            included_blobs.merge link[:node].get_included_blobs
                          end
                          included_blobs
                        end
  end

  def get_problem_blobs
    @problem_blobs
  end

  def get_effective_size
    @size_deep ||= begin
      included_blobs = get_included_blobs
      size_deep = 0
      included_blobs.each do |blob_sha256|
        size_deep += CachesManager.blob_size(blob_sha256) unless CachesManager.blob_size(blob_sha256).nil? || CachesManager.blob_size(blob_sha256) == -1
      end
      size_deep
    end
  end

  def add_links_by_config(n, path)
    config_sha256 = n[:config][:digest].split(':').last
    @links << { path: path.nil? ? ['config'] : path + ['config'], node: CachesManager.get_node(n[:config][:mediaType], config_sha256, n[:config][:size]) }
    config_json = CachesManager.json_blob_content(config_sha256)
    if !config_json[:history].nil? && config_json[:history].size > 0
      history_without_empty_layers = config_json[:history].reject { |h| !h[:empty_layer].nil? && h[:empty_layer] }
      n[:layers].each_with_index do |layer, id|
        @links << { path: path.nil? ? ["layers/#{id}"] : path + ["layers/[#{id}]"], node: CachesManager.get_node(layer[:mediaType], layer[:digest].split(':').last, layer[:size]) }
        # @links.last[:node].set_created_by history_without_empty_layers[id][:created_by][0..10]
        @links.last[:node].set_created_by history_without_empty_layers[id][:created_by]
        @links.last[:node].set_created_at history_without_empty_layers[id][:created]
      end
    else
      n[:layers].each_with_index do |layer, id|
        @links << { path: path.nil? ? ["layers/#{id}"] : path + ["layers/[#{id}]"], node: CachesManager.get_node(layer[:mediaType], layer[:digest].split(':').last, layer[:size]) }
      end
    end
  end
end


#     begin
#         if !CachesManager.is_refreshing_in_progress?
#           if RegistryExplorerFront.get_session.nil? || RegistryExplorerFront.get_session[:attestations_exploring]
#             if json_blob_content[:predicate] && json_blob_content[:predicate].is_a?(Hash)
#               json_blob_content[:predicate].delete(:materials)
#             end
#           else
#             return
#           end
#         else
#           if CachesManager.is_refreshing_in_progress_no_attest?
#             return
#           elsif CachesManager.is_refreshing_in_progress_with_attest?
#             if json_blob_content[:predicate] && json_blob_content[:predicate].is_a?(Hash)
#               json_blob_content[:predicate].delete(:materials)
#             end
#           end
#         end
#       rescue Exception => e
#         puts "Error when processing toto json: #{e}"
#         return
#       end