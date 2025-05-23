require 'benchmark'
require_relative '../utils/Node'
require_relative '../utils/file_utils'
require_relative '../utils/time_measurer'

def load_tree
  images = Set.new
  TimeMeasurer.start_measurement

  tree = { children: {}, image: {}, total_images_amount: 0, required_blobs: Set.new, problem_blobs: Set.new }

  flattened = nil
  extract_images(images)
  required_in_registry_blobs = Set.new
  problem_blobs = Set.new
  images.each do |image|
    required_in_registry_blobs.merge(image[:required_blobs])
    problem_blobs.merge(image[:problem_blobs])
  end
  TimeMeasurer.measure(:building_tree) do
    build_tree(images, tree)
  end
  TimeMeasurer.measure(:flatten_tree) do
    flattened = flatten_tree(tree)
  end
  puts TimeMeasurer.log_measurers
  puts "Flattened tree size: #{flattened.size}"
  [flattened, images, problem_blobs, required_in_registry_blobs]
end

def load_image_tree(image_path)
  TimeMeasurer.start_measurement

  tree = { children: {}, image: {}, total_images_amount: 0, required_blobs: Set.new, problem_blobs: Set.new }

  flattened = nil
  images = [extract_image_with_tags(image_path)]
  required_in_registry_blobs = Set.new
  problem_blobs = Set.new
  images.each do |image|
    required_in_registry_blobs.merge(image[:required_blobs])
    problem_blobs.merge(image[:problem_blobs])
  end
  TimeMeasurer.measure(:building_tree) do
    build_tree(images, tree)
  end
  TimeMeasurer.measure(:flatten_tree) do
    flattened = flatten_tree(tree)
  end
  puts TimeMeasurer.log_measurers
  puts "Flattened tree size: #{flattened.size}"
  [flattened, images, problem_blobs, required_in_registry_blobs]
end