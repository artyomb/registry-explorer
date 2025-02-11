class Node
  def initialize(type, sha256, node_size = nil, required_blobs = nil, unique_blobs_sizes = nil)
    @type = type
    @sha256 = sha256
    @node_size = node_size
    @created_at = define_create_time sha256
    @links = []
    @created_at = nil
    @created_by = nil
    begin
      @actual_blob_size = blob_size(@sha256)
      unique_blobs_sizes[sha256] = @actual_blob_size unless unique_blobs_sizes.nil?
    rescue Exception => e
      puts "Error: #{e}"
      @actual_blob_size = -1
    end
    return unless @type.to_s =~ /json/
    find_links(JSON.parse(blob_content(@sha256), symbolize_names: true), [], unique_blobs_sizes)
  end

  def find_links(n, path = [], unique_blobs_sizes = nil)
    return unless (n.is_a? Hash or n.is_a? Array)
    if n.is_a? Hash
      if !(n.key?(:config) && n[:config].key?(:digest) && n.key?(:layers))
        n.each do |key, value|
          if value.is_a? Hash
            add_link(path + [key], value, unique_blobs_sizes) if value.key? :digest
            find_links(value, path + [key], unique_blobs_sizes)
          elsif value.is_a? Array
            find_links(value, path + [key], unique_blobs_sizes)
          end
        end
      else
        add_links_by_config(n, path, unique_blobs_sizes)
      end
    elsif n.is_a? Array
      n.each_with_index do |sub_hash, id|
        if sub_hash.is_a? Hash
          add_link(path + ["[#{id}]"], sub_hash, unique_blobs_sizes) if sub_hash.key? :digest
          find_links(sub_hash, path + ["[#{id}]"])
        end
      end
    end
  end

  def add_link(path, value, unique_blobs_sizes = nil)
    digest_val = value[:digest]
    sha256 = digest_val.is_a?(Hash) ? digest_val[:sha256] : digest_val.split(':').last
    @links << { path:, node: Node.new(value[:mediaType], sha256, value[:size], nil, unique_blobs_sizes) }
    puts("Noode #{sha256} with type #{@type} added link to node #{@links.last}")
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

  def get_included_blobs(included_blobs = Set.new)
    included_blobs.add(@sha256)
    @links.each do |link|
      link[:node].get_included_blobs(included_blobs)
    end
    included_blobs
  end

  def get_size_deep(unique_blobs_sizes = nil)
    included_blobs = get_included_blobs
    size_deep = 0
    included_blobs.each do |blob_sha256|
      size_deep += unique_blobs_sizes[blob_sha256] unless unique_blobs_sizes.nil?
    end
    size_deep
  end

  def add_links_by_config(n, path, unique_blobs_sizes)
    config_sha256 = n[:config][:digest].split(':').last
    @links << { path: path.nil? ? ['config'] : path + ['config'], node: Node.new(n[:config][:mediaType], config_sha256, n[:config][:size], nil, unique_blobs_sizes) }
    config_json = JSON.parse(blob_content(config_sha256), symbolize_names: true)
    if !config_json[:history].nil? && config_json[:history].size > 0
      history_without_empty_layers = config_json[:history].reject { |h| !h[:empty_layer].nil? && h[:empty_layer] }
      n[:layers].each_with_index do |layer, id|
        @links << { path: path.nil? ? ["layers/#{id}"] : path + ["layers/[#{id}]"], node: Node.new(layer[:mediaType], layer[:digest].split(':').last, layer[:size], nil, unique_blobs_sizes) }
        @links.last[:node].set_created_by history_without_empty_layers[id][:created_by]
        @links.last[:node].set_created_at history_without_empty_layers[id][:created]
      end
    else
      n[:layers].each_with_index do |layer, id|
        @links << { path: path.nil? ? ["layers/#{id}"] : path + ["layers/[#{id}]"], node: Node.new(layer[:mediaType], layer[:digest].split(':').last, layer[:size], nil, unique_blobs_sizes) }
      end
    end
  end
end