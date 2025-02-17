def get_service_version
  File.read(Dir.pwd + "/.version").strip
end