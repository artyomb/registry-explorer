def get_service_version
  File.read(Dir.pwd + "/.version").strip
end


def calculate_unique_duration(time_ranges)
  # Sort time ranges by start time
  sorted = time_ranges.sort_by { |range| range[:start] }

  merged = []

  sorted.each do |range|
    if merged.empty? || merged.last[:end] < range[:start]
      # No overlap, add new interval
      merged << range.dup
    else
      # Merge overlapping intervals
      merged.last[:end] = [merged.last[:end], range[:end]].max
    end
  end

  # Calculate total duration
  total_duration = merged.sum { |range| range[:end] - range[:start] }
  total_duration
end
