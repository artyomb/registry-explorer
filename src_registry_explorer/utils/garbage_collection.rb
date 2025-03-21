# require_relative '../utils/time_measurer'
# TimeMeasurer.start_measurement
# require_relative '../sinatra/sinatra_server'
# require_relative '../utils/common_utils'
require_relative 'file_utils'

def get_images_strictire_where_indexes_without_revisions(images_structure = Set.new)
  images_paths = get_images_paths
  images_paths.each do |image_path|
    subfolders = image_path.split('/')
    image_name = "/" + subfolders[subfolders.find_index('repositories') + 1..].join('/')
    current_img = { name: image_name, tags: Set.new, total_size: -1, required_blobs: Set.new, problem_blobs: Set.new }
    tag_paths = Dir.glob(image_path + "/_manifests/tags/*").select { |f| File.directory?(f) }
    tag_paths.map { |tag_path| extract_tag_with_unlinked_indexes(tag_path) }.each do |tag|
      current_img[:tags].add(tag)
      current_img[:required_blobs].merge(tag[:required_blobs])
      current_img[:problem_blobs].merge(tag[:problem_blobs])
    end
    next if current_img[:tags].empty?
    images_structure.add current_img
    current_img[:total_size] = CachesManager.get_repo_size(image_path, current_img[:required_blobs])
  end
  images_structure
end

def extract_tag_with_unlinked_indexes(tag_path)
  current_tag = { name: tag_path.split('/').last, index_Nodes: [], required_blobs: Set.new, size: -1, problem_blobs: Set.new }
  indexes_paths = Dir.glob(tag_path + "/index/sha256/*")
  index_without_problems = []
  problem_indexes = []
  indexes_paths.each do |index_path|
    index_sha256 = index_path.split('/').last
    next if File.exist?(tag_path + "/../../revisions/sha256/#{index_sha256}/link")
    cur_index = extract_index(index_sha256)
    if cur_index[:node].get_problem_blobs.size > 0
      problem_indexes << cur_index
    else
      index_without_problems << cur_index
    end
  end
  index_without_problems.sort_by! { _1[:node]&.created_at || '-' }.reverse!
  current_tag[:index_Nodes].append(*index_without_problems)
  current_tag[:index_Nodes].append(*problem_indexes)
  current_tag[:index_Nodes].map do |index_node|
    current_tag[:required_blobs].merge index_node[:node].get_included_blobs
    current_tag[:problem_blobs].merge index_node[:node].get_problem_blobs
  end
  current_tag[:size] = CachesManager.get_repo_size(tag_path, current_tag[:required_blobs])
  current_tag
end

def get_all_revisions_set(revisions_linked_no_blob, revisions_linked_has_blob, revisions_no_link_no_blob, revisions_no_link_has_blob)
  revisions_linked_no_blob + revisions_linked_has_blob + revisions_no_link_no_blob + revisions_no_link_has_blob
end

def get_images_structure_affected_by_gc(images_structure = Set.new, required_blobs)
  images_paths = get_images_paths
  images_paths.each do |image_path|
    subfolders = image_path.split('/')
    image_name = "/" + subfolders[subfolders.find_index('repositories') + 1..].join('/')
    current_img = { name: image_name, tags: Set.new, layers: Set.new, revisions: Set.new, required_blobs: Set.new, problem_blobs: Set.new }
    tag_paths = Dir.glob(image_path + "/_manifests/tags/*").select { |f| File.directory?(f) }
    tag_paths.map { |tag_path| extract_tag_with_unlinked_indexes(tag_path) }.each do |tag|
      current_img[:tags].add(tag)
      current_img[:required_blobs].merge(tag[:required_blobs])
      current_img[:problem_blobs].merge(tag[:problem_blobs])
    end
    Dir.children(File.join(image_path,'_layers', 'sha256')).each{ |l| current_img[:layers].add l if !required_blobs.include?(l) }
    Dir.children(File.join(image_path, '_manifests', 'revisions', 'sha256')).each{ |l| current_img[:revisions].add l if !required_blobs.include?(l) }
    images_structure.add current_img
    current_img[:total_size] = CachesManager.get_repo_size(image_path, current_img[:required_blobs])
  end

  images_structure
end

def get_images_structure_tags_wth_only_current(images_structure = Set.new)
  images_paths = get_images_paths
  images_paths.each do |image_path|
    subfolders = image_path.split('/')
    image_name = "/" + subfolders[subfolders.find_index('repositories') + 1..].join('/')
    current_img = { name: image_name, tags: Set.new, total_size: -1, required_blobs: Set.new, problem_blobs: Set.new }
    tag_paths = Dir.glob(image_path + "/_manifests/tags/*").select { |f| File.directory?(f) }
    tag_paths.map { |tag_path| extract_tag_current_only(tag_path) }.each do |tag|
      current_img[:tags].add(tag)
      current_img[:required_blobs].merge(tag[:required_blobs])
      current_img[:problem_blobs].merge(tag[:problem_blobs])
    end
    next if current_img[:tags].empty?
    images_structure.add current_img
    current_img[:total_size] = CachesManager.get_repo_size(image_path, current_img[:required_blobs])
  end
  images_structure
end

def extract_tag_current_only(tag_path)
  current_tag = { name: tag_path.split('/').last, index_Nodes: [], current_index_sha256: CachesManager.get_index_sha256(tag_path + "/current/link"), required_blobs: Set.new, size: -1, problem_blobs: Set.new }
  indexes_paths = Dir.glob(tag_path + "/index/sha256/*")
  current_tag[:index_Nodes] << extract_index(current_tag[:current_index_sha256])
  current_tag[:index_Nodes].map do |index_node|
    current_tag[:required_blobs].merge index_node[:node].get_included_blobs
    current_tag[:problem_blobs].merge index_node[:node].get_problem_blobs
  end
  current_tag[:size] = CachesManager.get_repo_size(tag_path, current_tag[:required_blobs])
  current_tag
end
