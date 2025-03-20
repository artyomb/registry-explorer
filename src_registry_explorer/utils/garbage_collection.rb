# require_relative '../utils/time_measurer'
# TimeMeasurer.start_measurement
# require_relative '../sinatra/sinatra_server'
# require_relative '../utils/common_utils'
# stored_blobs = nil
# stored_blobs_size = nil
# required_blobs = nil
# required_blobs_size = nil
# unused_blobs = nil
# unused_blobs_size = nil
# not_existing_blobs = Set.new
# blobs_set = Set.new
# images = extract_images()
# TimeMeasurer.start_measurement
# TimeMeasurer.measure(:calculate_disk_usage) do
#   blobs_path = $base_path + '/blobs/sha256'
#   required_blobs = images.map { _1[:required_blobs] }.reduce(Set.new, :merge)
#   stored_blobs = Set.new
#   Dir.children(blobs_path).each do |path|
#     current_blobs = Dir.children(File.join(blobs_path, path))
#     stored_blobs.merge(current_blobs)
#     current_blobs.each { |blob| blobs_set.add({ "sha256" => blob, "size" => CachesManager.blob_size(blob), "is_required" => required_blobs.include?(blob) }) }
#   end
#   # TODO: implement exploring unnecessary blobs
#   puts "Directory size: #{represent_size(Dir.glob(File.join(blobs_path, '**', '*')) # Get all files and subdirectories
#                                             .select { |file| File.file?(file) } # Filter only files
#                                             .sum { |file| File.size(file) })}"
#   unused_blobs = stored_blobs - required_blobs
#   not_existing_blobs = required_blobs - stored_blobs
#   required_blobs_size = required_blobs.map { |b| CachesManager.blob_size(b) }.sum
#   stored_blobs_size = stored_blobs.map { |b| CachesManager.blob_size(b) }.sum
#   unused_blobs_size = unused_blobs.map { |b| CachesManager.blob_size(b) }.sum
#   disk_size_tooltip = "title:" +
#     "Disk usage is calculated as the sum of all blobs in the registry.<br><br>" +
#     "Actual data:<br>" +
#     "#{required_blobs.size} required blobs disk usage: #{represent_size(required_blobs_size)}<br>" +
#     "#{stored_blobs.size} stored blobs disk usage: #{represent_size(stored_blobs_size)}<br>" +
#     "#{unused_blobs.size} unused blobs disk usage: #{represent_size(unused_blobs_size)}<br>" +
#     "#{not_existing_blobs.size} not existing blobs"
# end
# TimeMeasurer.log_measurers
#
# # Exploring each revisions directory (suggestion: even if blob is unused in any tag index, it still can be used in other revisions despite they are not referenced)
# images_paths = get_images_paths
# garbage_collect_canditages_from_registry = ['31915bebabb2e9de360869d1fb71917e7f0e8ed814d483ca425144e71c237fdf','d8851bb3e1c298c84c77f486cec87ca56035f7aa56b9daf2b987cc48d1ef4b95','ebe782acfd83531261686970471721f3ed2292d1b341e1afd30d79f2af56bded','04bee404a558cb23a801aae4abc05db6b0065a49816c59ce27977e977a37673d','04d85f9738fe85453c94ca0d457ca905f52d4926cfb279ca545ca8dda0b3e071','2077fd69ff515c07c761bc400837c22fd95878e7aaf127d5635ab16bb02f6dc9','23d37d1ffa68179281e84b389c3fd64afcb4d730081efeec5cc3fe1603e998b3','2cfb01b98e5f89a22a9656e2f6371aa62ff5e3d78cbf6f57894067de37c8887a','63f42ca083acaf0e7cbf172ff42cc75aa0d9f8a6e3aecfd16ce2a62a7fe98d17','d9df24e0fb42be9542105fd3de578b37155310d276e81913e6050ac210199754','e0b54c2137422f8f4da26a89a63387359732c8ae8cf9259fb7e984e41887ee4e']
#
# revisions_no_link_has_blob = Set.new
# revisions_no_link_no_blob = Set.new
# revisions_linked_has_blob = Set.new
# revisions_linked_no_blob = Set.new
# images_paths.each do |image_path|
#   revisions_paths = Dir.children(File.join(image_path, '_manifests', 'revisions', 'sha256'))
#   revisions_paths.each do |revision_path|
#     # Check revisions without link
#     if !File.exist?(File.join(image_path, '_manifests', 'revisions', 'sha256', revision_path, 'link'))
#       if stored_blobs.include?(revision_path)
#         revisions_no_link_has_blob.add(revision_path)
#       else
#         revisions_no_link_no_blob.add(revision_path)
#       end
#     else
#       if stored_blobs.include?(revision_path)
#         revisions_linked_has_blob.add(revision_path)
#       else
#         revisions_linked_no_blob.add(revision_path)
#       end
#     end
#   end
# end
#
# puts "Revisions without link with blob: #{revisions_no_link_has_blob.size}"
# puts garbage_collect_canditages_from_registry.all? { |revision_path| revisions_no_link_has_blob.include?(revision_path) }
# #node_from_revision |= begin
# #                             Node.new(revision_path, image_path)
# #                           rescue StandardError => e
# #                             puts "Error while creating node from revision #{revision_path} from image #{image_path}: #{e.message}"
# #                             nil
# #                           end
# garbage_collect_candidates_nodes = []
# revisions_no_link_has_blob.each do |revision_path|
#   garbage_collect_candidates_nodes << Node.new(nil, revision_path)
# end
# all_blobs_from_garbage_collect_candidates = Set.new
# garbage_collect_candidates_nodes.each do |node|
#   all_blobs_from_garbage_collect_candidates.merge(node.get_included_blobs)
# end
# all_unused_garbage_collect_candidate_blobs = all_blobs_from_garbage_collect_candidates.select{|b| unused_blobs.include?(b) }
# revisions_linked_has_blob_nodes = []
# revisions_linked_has_blob.each do |revision_path|
#   revisions_linked_has_blob_nodes << Node.new(nil, revision_path)
# end
# all_blobs_from_revisions_linked_has_blob = Set.new
# revisions_linked_has_blob_nodes.each do |node|
#   all_blobs_from_revisions_linked_has_blob.merge(node.get_included_blobs)
# end
# unused_revisions = Set.new
# revisions_linked_has_blob.each do |revision_path|
#   unused_revisions.add(revision_path) if unused_blobs.include?(revision_path)
# end
# unused_revisions_nodes = []
# unused_revisions.each do |revision_path|
#   unused_revisions_nodes << Node.new(nil, revision_path)
# end
# unused_revisions_blobs = Set.new
# unused_revisions_nodes.each do |node|
#   unused_revisions_blobs.merge(node.get_included_blobs)
# end
#
# actually_unused_blobs = unused_revisions_blobs.select{ |b| unused_blobs.include?(b) }
# if actually_unused_blobs.select{ |b| unused_revisions.include?(b) }.size != unused_revisions.size
#   raise "Not all unused revisions have unused blobs"
# end
# actually_unused_blobs_size = 0
# actually_unused_blobs.each do |blob|
#   actually_unused_blobs_size += CachesManager.blob_size(blob)
# end
# puts "All blobs from revisions linked with blob: #{all_blobs_from_revisions_linked_has_blob.size}"