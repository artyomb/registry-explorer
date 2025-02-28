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



def define_create_time(sha256)
  begin
    file = File.join($base_path + "/blobs/sha256/#{sha256[0..1]}/#{sha256}/data")
    Time.at(File.ctime(file))
  rescue Exception => e
    puts "Error in defining create time: #{e}"
    return nil
  end
  nil
end


def represent_size(bytes)
  begin
    # bytes.to_s.gsub(/(\d)(?=(\d{3})+(?!\d))/, '\\1,')
    units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB']
    return '0 B' if bytes == 0

    exp = (Math.log(bytes) / Math.log(1024)).to_i
    exp = units.size - 1 if exp > units.size - 1
    size = bytes.to_f / (1024 ** exp)

    format('%.2f %s', size, units[exp])
  rescue Exception => e
    puts "Error in size representing: #{e}"
    '-'
  end
end


def represent_datetime(datetime_str)
  begin
    # Parse the datetime string into a Time object
    time_obj = Time.parse(datetime_str)
    # Format the Time object into the desired format
    time_obj.strftime('%Y-%m-%d %H:%M:%S')
  rescue Exception => e
    puts "Error in representing datetime: #{e}"
    '-'
  end
end