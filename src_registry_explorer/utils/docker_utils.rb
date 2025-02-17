def get_container_id
  cgroup_file = "/proc/self/cgroup"
  return nil unless File.exist?(cgroup_file)

  File.foreach(cgroup_file) do |line|
    if line.include?("docker")
      return line.split("/").last.strip
    end
  end

  nil
end

def get_image_tag
  container_id = get_container_id
  return nil unless container_id

  inspect_data = `docker inspect #{container_id} 2>/dev/null`
  parsed_data = JSON.parse(inspect_data)
  parsed_data[0]['Config']['Image'] rescue nil
end