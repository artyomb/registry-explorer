require_relative 'caches_manager'
require_relative 'file_utils'
def clean_up_image_tag(image_path, tag, conditions)
  return if conditions.nil? || conditions.empty?
  puts "Cleaning up tag #{tag} from image #{image_path}: with conditions: #{conditions}"
  full_tag_path = File.join($base_path, "repositories", image_path, "_manifests/tags", tag)
  extracted_tag = extract_tag(full_tag_path)
  marked_to_retain = Set.new([extracted_tag[:current_index_sha256]])

  nodes_with_known_date = []

  nodes_with_unknown_date = []

  extracted_tag[:index_Nodes].reject { |node_link| node_link[:node].sha256 == extracted_tag[:current_index_sha256] }.each { |node_link| (node_link[:node].created_at.nil? ? nodes_with_unknown_date << node_link : nodes_with_known_date << node_link) }

  sorted_nodes_with_known_date = nodes_with_known_date.sort_by { |node_link| node_link[:node].created_at }

  if !conditions[:at_least_to_retain_number].nil? && conditions[:at_least_to_retain_number] > 0
    must_retain_number = conditions[:at_least_to_retain_number]
    remaining_to_retain = must_retain_number - marked_to_retain.size

    if remaining_to_retain > 0
      sorted_nodes_with_known_date.each do |node_link|
        marked_to_retain.add(node_link[:node].sha256)
        remaining_to_retain -= 1
        break if remaining_to_retain <= 0
      end

      if remaining_to_retain > 0
        nodes_with_unknown_date.each do |node_link|
          marked_to_retain.add(node_link[:node].sha256)
          remaining_to_retain -= 1
          break if remaining_to_retain <= 0
        end
      end
    end
  end

  if !conditions[:deadline_to_retain].nil? && !conditions[:deadline_to_retain].empty? && Time.parse(conditions[:deadline_to_retain]).is_a?(Time)
    deadline_to_retain = Time.parse(conditions[:deadline_to_retain])
    sorted_nodes_with_known_date.each do |node_link|
      if Time.parse(node_link[:node].created_at) >= deadline_to_retain
        marked_to_retain.add(node_link[:node].sha256)
      end
    end
  end

  deleted_indexes = 0
  errors = []

  extracted_tag[:index_Nodes].each do |node_link|
    if marked_to_retain.include?(node_link[:node].sha256)
      next
    else
      begin
        message = delete_index_soft(image_path, tag, node_link[:node].sha256)
        deleted_indexes += 1
        puts message
      rescue StandardError => e
        errors << e.message
        puts "Error while deleting index #{node_link[:node].sha256} from #{full_tag_path}: #{e}"
        raise e
      end
    end
  end
  "#{deleted_indexes} were deleted.\n#{errors.size} errors: #{errors.join(', ')}"
end