#!/bin/env ruby
require 'sinatra/base'
require 'slim'
require 'rack/sassc'
require 'uri'
require 'net/http'
require 'cgi'
require_relative '../utils/file_utils'
require_relative '../utils/garbage_collection'
require 'open3'

class RegistryExplorerFront < Sinatra::Base
  use Rack::SassC, css_location: "#{__dir__}/../public/css", scss_location: "#{__dir__}/../css",
      create_map_file: true, syntax: :sass, check: true
  use Rack::Static, urls: %w[/css /js], root: "#{__dir__}/public/", cascade: true

  FileUtils.mkdir_p($temp_dir) unless Dir.exist?($temp_dir)

  enable :sessions

  @@current_session = nil

  before do
    session[:attestations_exploring] ||= false
    @@current_session = session
  end

  CachesManager.start_auto_refresh
  set :root, '.' #File.dirname(__FILE__)
  get '/',         &->() { slim :index }
  get '/index',         &->() { slim :index }
  get '/tag-exploring/*' do
    full_tag_path = params[:splat].first || ''
    slim :tag_exploring, locals: { full_tag_path: full_tag_path }
  end
  get '/image-exploring/*' do
    tag_image_path = params[:splat].first || '' # expect following url: /image-exploring/re/po/si/to/ry/tag_name/imgsha256
    if tag_image_path.include?('sha256:')
      slim :image_exploring, locals: { tag_image_path: tag_image_path }
    else
      slim :image_with_tags_exploring, locals: { tag_image_path: tag_image_path }
    end

  end
  get '/blob-exploring/:sha256', &->() {
    json_content = begin
                      CachesManager.json_blob_content(params[:sha256])
                    rescue StandardError => e
                      nil
                    end
    if json_content
      redirect "/json/#{params[:sha256]}"
    else
      redirect "/tar-gz/#{params[:sha256]}"
    end
  }
  get '/json/:sha256', &->() { slim :json }
  get '/tar-gz/:sha256', &->() { slim :targz }

  get '/test', &->() { slim :test }

  get '/file-in-archive/*' do
    path_data = params[:splat].first.split('/$path/')
    blob_sha256 = path_data[0]
    file_path = path_data[1]
    content = extract_file_content_from_archive_by_path(blob_sha256, file_path)
    extention = File.extname(file_path).delete_prefix('.')
    escaped_content = CGI.escapeHTML(content)
    "<code class='language-#{extention}'>#{escaped_content}</code>"
  end

  get '/healthcheck', &-> { 'Healthy' }

  get '/debug' do
    session.inspect
  end

  get '/get-in-session-attestations-exploring' do
    session[:attestations_exploring].nil? ? 'false' : session[:attestations_exploring].to_s
  end

  put '/set-in-session-attestations-exploring' do
    puts "Setting session[:attestations_exploring] to #{params[:new_value]}\nPrevious value: #{session[:attestations_exploring]}"
    if params[:new_value] == 'true'
      params[:new_value] = true
    elsif params[:new_value] == 'false'
      params[:new_value] = false
    else
      return [400, 'Error: new_value should be true or false']
    end
    session[:attestations_exploring] = params[:new_value]
    puts "Session[:attestations_exploring] set to #{session[:attestations_exploring]}"
    [200, 'OK']
  end

  delete '/delete-image/*' do
    if $read_only_mode
      return [403, 'Registry is in read-only mode']
    end
    path_data = params[:splat].first.split('/$sha256/')
    image_path = path_data[0]
    image_sha256 = path_data[1]
    if params[:soft] == 'false'
      return delete_index(image_path, image_sha256, false)
    else
      [400, 'Error when deleting image: soft delete is not supported yet']
    end

  end


  delete '/delete-tag/*' do
    path_data = params[:splat].first.split('/$sha256/')
    image_path = path_data[0]
    image_sha256 = path_data[1] if path_data.size == 2
    if params[:soft] == 'false'
      return delete_index(image_path, image_sha256, true)
    else
      return [400, 'Error when deleting tag: specify tag name'] if params[:tag].nil?
      return delete_image_tag_soft(image_path, params[:tag])
    end
  end

  delete '/delete-tag' do
    boby = request.body.read
    data = JSON.parse(boby, symbolize_names: true)
    if data.nil? || data[:images_with_tags].nil?
      return [400, 'Error when deleting list of tags: no data to delete']
    end
    number_of_deleted_tags = 0
    exceptions = []
    data[:images_with_tags].each do |image_with_tags|
      image_path, tag = image_with_tags.split(':')
      puts "Deleting tag #{tag} from image #{image_path}:"
      begin
        if params[:soft] == 'false'
          delete_image_tag(image_path[1..], tag)
          number_of_deleted_tags += 1
        else
          delete_image_tag_soft(image_path[1..], tag)
          number_of_deleted_tags += 1
        end
      rescue StandardError => e
        exceptions << e.message
      end
    end
    puts "Deleting #{number_of_deleted_tags} tags is successful. #{exceptions.size} exceptions raised:#{exceptions.join("\n")}"
    [200, "Deleting #{number_of_deleted_tags} tags is successful. #{exceptions.size} exceptions raised"]
  end

  delete '/delete-non-current-images/*' do
    path_data = params[:splat].first.split('/$sha256/')
    url_image_path = path_data[0].split('/')[0..-2].join('/')
    image_path = $base_path + '/repositories/' + url_image_path
    tag = path_data[0].split('/').last
    tag_path = image_path + '/_manifests/tags/' + tag
    current_image_sha256 = path_data[1]
    list_of_non_current_images_sha256_to_delete = Dir.children(tag_path + '/index/sha256').select { |sha256| sha256 != current_image_sha256 && File.exist?("#{tag_path}/../../revisions/sha256/#{sha256}/link") }
    error_messages_collector = []
    list_of_non_current_images_sha256_to_delete.each do |sha256|
      begin
        if params[:soft] == 'false'
          delete_index(url_image_path, sha256, false)
        else
          return [400, 'Error when deleting image: soft delete is not supported yet']
        end
      rescue StandardError => e
        error_messages_collector << e.message
      end
    end
    if error_messages_collector.empty?
      [200, 'All images deleted successfully']
    else
      [500, "Errors, occurred when deleting images: #{error_messages_collector.join('; ')}"]
    end
  end

  get '/registry-healthcheck' do
    slim :registry_healthcheck
  end

  get '/revisions' do
    slim :revisions
  end

  get '/garbage-collection' do
    if params[:with_history] == 'true'
      slim :garbage_collection_with_history
    elsif params[:with_history] == 'false'
      slim :garbage_collection
    end
  end

  get '/garbage-collection-data' do
    session = RegistryExplorerFront.get_session
    previous_session_flag = session[:attestations_exploring]
    session[:attestations_exploring] = true
    CachesManager.execute_refresh_pipeline
    # EXPLORING BLOBS FOR FURTHER GARBAGE COLLECTION
    stored_blobs = Set.new
    stored_blobs_size = 0
    required_blobs = Set.new
    required_blobs_size = 0
    unused_blobs = Set.new
    unused_blobs_size = 0
    not_existing_blobs = Set.new
    blobs_set = Set.new
    images = nil
    if params[:with_history] == "false"
      images = extract_images()
    elsif params[:with_history] == "true"
      images = get_images_structure_tags_wth_only_current()
    end
    TimeMeasurer.start_measurement
    TimeMeasurer.measure(:calculate_disk_usage) do
      blobs_path = $base_path + '/blobs/sha256'
      required_blobs = images.map { _1[:required_blobs] }.reduce(Set.new, :merge)
      stored_blobs = Set.new
      Dir.children(blobs_path).each do |path|
        current_blobs = Dir.children(File.join(blobs_path, path))
        stored_blobs.merge(current_blobs)
        current_blobs.each { |blob| blobs_set.add({ "sha256" => blob, "size" => CachesManager.blob_size(blob), "is_required" => required_blobs.include?(blob) }) }
      end
      puts "Directory size: #{represent_size(Dir.glob(File.join(blobs_path, '**', '*')) # Get all files and subdirectories
                                                .select { |file| File.file?(file) } # Filter only files
                                                .sum { |file| File.size(file) })}"
      unused_blobs = stored_blobs - required_blobs
      not_existing_blobs = required_blobs - stored_blobs
      required_blobs_size = required_blobs.map { |b| CachesManager.blob_size(b) }.sum
      stored_blobs_size = stored_blobs.map { |b| CachesManager.blob_size(b) }.sum
      unused_blobs_size = unused_blobs.map { |b| CachesManager.blob_size(b) }.sum
    end
    TimeMeasurer.log_measurers
    ####################################################################################################################################
    affected_images_structure = get_images_structure_affected_by_gc(Set.new, required_blobs)
    ####################################################################################################################################

    rows_in_table = []
    if params[:with_history] == "false"
      rows_in_table << {image_name: "Total", unreferenced_indexes: affected_images_structure.map{ |image| image[:tags].map{ |tag| tag[:index_Nodes].size }.sum }.sum, unused_revision: affected_images_structure.map{ |i| i[:revisions].size}.sum, unused_layers: affected_images_structure.map{ |i| i[:layers].size}.sum }
      affected_images_structure.each do |image|
        rows_in_table << { image_name: image[:name], unreferenced_indexes: image[:tags].map{ |tag| tag[:index_Nodes].size }.sum, unused_revision: image[:revisions].size, unused_layers: image[:layers].size }
      end
    elsif params[:with_history] == "true"
      rows_in_table << { image_name: "Total", unused_revision: affected_images_structure.map{ |i| i[:revisions].size}.sum, unused_layers: affected_images_structure.map{ |i| i[:layers].size}.sum }
      affected_images_structure.each do |image|
        rows_in_table << { image_name: image[:name], unused_revision: image[:revisions].size, unused_layers: image[:layers].size }
      end
    end
    session[:attestations_exploring] = previous_session_flag
    response_body = {
      stored_blobs_amount: stored_blobs.size,
      stored_blobs_size: represent_size(stored_blobs_size),
      unused_blobs_amount: unused_blobs.size,
      unused_blobs_size: represent_size(unused_blobs_size),
      rows_in_table: rows_in_table
    }.to_json
    body response_body
  end

  delete '/perform-garbage-collection' do
    raise(StandardError, "You can't perform garbage collection as you boot your service in read-only mode") if $read_only_mode
    #
    request_body = JSON.parse(request.body.read, symbolize_names: true)
    session = RegistryExplorerFront.get_session
    previous_session_flag = session[:attestations_exploring]
    session[:attestations_exploring] = true
    status, message = perform_gc(request_body[:blobs])
    session[:attestations_exploring] = previous_session_flag
    [status, message]
  end

  get '/blobs-exploring',         &->() { slim :blobs_exploring }

  post '/tag-from-image' do
    boby = request.body.read
    data = JSON.parse(boby, symbolize_names: true)

    # current_image_str = data[:image]
    # new_tag_string = data[:new_tag]
    #
    # current_image_str = current_image_str.gsub('localhost:7000', 'localhost:5000') if !ENV['DBG'].nil?
    # new_tag_string = new_tag_string.gsub('localhost:7000', 'localhost:5000') if !ENV['DBG'].nil?
    # return [400, "Please provide a valid image string and tag string."] if current_image_str.nil? || new_tag_string.nil?
    #
    # # healthcheck docker
    # docker_cmd = ['docker', 'version']
    # puts "Running command to check docker version: #{docker_cmd.join(' ')}"
    # docker_output, docker_err, docker_status = Open3.capture3(*docker_cmd)
    # if !docker_status.success?
    #   error_message = "Failed to check docker version: #{docker_err}"
    #   return [400, error_message]
    # end
    #
    # pull_cmd = ['docker', 'pull', current_image_str]
    # puts "Running command to pull image: #{pull_cmd.join(' ')}"
    # pull_output, pull_err, pull_status = Open3.capture3(*pull_cmd)
    # if !pull_status.success?
    #   error_message = "Failed to pull image: #{pull_err}"
    #   puts "Failed to pull image: #{pull_err}"
    #   return [400, error_message]
    # end
    #
    # tag_cmd = ['docker', 'tag', current_image_str, new_tag_string]
    # puts "Running command to tag image: #{tag_cmd.join(' ')}"
    # tag_output, tag_err, tag_status = Open3.capture3(*tag_cmd)
    # if !tag_status.success?
    #   error_message = "Failed to tag image: #{tag_err}"
    #   puts "Failed to tag image: #{tag_err}"
    #   return [400, error_message]
    # end
    #
    # push_cmd = ['docker', 'push', new_tag_string]
    # puts "Running command to push image: #{push_cmd.join(' ')}"
    # push_output, push_err, push_status = Open3.capture3(*push_cmd)
    # if !push_status.success?
    #   error_message = "Failed to push image: #{push_err}"
    #   puts "Failed to push image: #{push_err}"
    #   return [400, error_message]
    # end
    # [200, "Tag created successfully"]
    #############################################################################################
    path_to_image = data[:path_to_image]
    old_tag = data[:old_tag]
    new_tag = data[:new_tag]
    image_sha256 = data[:image_sha256]
    return [400, "Please provide a valid path to image, old tag, new tag and image sha256."] if path_to_image.nil? || old_tag.nil? || new_tag.nil? || image_sha256.nil?
    full_image_path = $base_path + "/repositories" + path_to_image
    return [400, "Please provide a valid path to image."] if !Dir.exist?(full_image_path + "/_manifests/tags")
    Dir.mkdir(full_image_path + "/_manifests/tags/" + new_tag) if !Dir.exist?(full_image_path + "/_manifests/tags/" + new_tag)
    Dir.mkdir(full_image_path + "/_manifests/tags/" + new_tag + "/current") if !Dir.exist?(full_image_path + "/_manifests/tags/" + new_tag + "/current")
    File.write(full_image_path + "/_manifests/tags/" + new_tag + "/current/link", "sha256:#{image_sha256}")

    Dir.mkdir(full_image_path + "/_manifests/tags/" + new_tag + "/index") if !Dir.exist?(full_image_path + "/_manifests/tags/" + new_tag + "/index")
    Dir.mkdir(full_image_path + "/_manifests/tags/" + new_tag + "/index/sha256") if !Dir.exist?(full_image_path + "/_manifests/tags/" + new_tag + "/index/sha256")
    Dir.mkdir(full_image_path + "/_manifests/tags/" + new_tag + "/index/sha256/#{image_sha256}") if !Dir.exist?(full_image_path + "/_manifests/tags/" + new_tag + "/index/sha256/#{image_sha256}")
    File.write(full_image_path + "/_manifests/tags/" + new_tag + "/index/sha256/#{image_sha256}/link", "sha256:#{image_sha256}")

    [200, "Tag created successfully"]
  end

  get '/blobs-exploring-data' do
    # REFRESHING CACHE WITH EXPLORING ATTESTATIONS
    session = RegistryExplorerFront.get_session
    previous_session_flag = session[:attestations_exploring]
    session[:attestations_exploring] = true
    CachesManager.execute_refresh_pipeline


    # CALCULATION OF DISK USAGE
    stored_blobs = nil
    stored_blobs_size = nil
    required_blobs = nil
    required_blobs_size = nil
    unused_blobs = nil
    unused_blobs_size = nil
    not_existing_blobs = Set.new
    blobs_set = Set.new
    images = extract_images()

    TimeMeasurer.start_measurement
    TimeMeasurer.measure(:calculate_disk_usage) do
      blobs_path = $base_path + '/blobs/sha256'
      required_blobs = images.map { _1[:required_blobs] }.reduce(Set.new, :merge)
      stored_blobs = Set.new
      Dir.children(blobs_path).each do |intermediate_path|
        current_blobs = Dir.children(File.join(blobs_path, intermediate_path))
        stored_blobs.merge(current_blobs)
        current_blobs.each { |blob| blobs_set.add(
          {
            "sha256" => blob, "size" => CachesManager.blob_size(blob),
            "is_required" => required_blobs.include?(blob),
            "created_at" => File.exist?(File.join(blobs_path, intermediate_path, blob)) ? File.mtime(File.join(blobs_path, intermediate_path, blob)) : '-',
          }
        ) }
      end
      puts "Directory size: #{represent_size(Dir.glob(File.join(blobs_path, '**', '*')) # Get all files and subdirectories
                                                .select { |file| File.file?(file) } # Filter only files
                                                .sum { |file| File.size(file) })}"
      unused_blobs = stored_blobs - required_blobs
      not_existing_blobs = required_blobs - stored_blobs
      required_blobs_size = required_blobs.map { |b| CachesManager.blob_size(b) }.sum
      stored_blobs_size = stored_blobs.map { |b| CachesManager.blob_size(b) }.sum
      unused_blobs_size = unused_blobs.map { |b| CachesManager.blob_size(b) }.sum
    end
    TimeMeasurer.log_measurers
    session[:attestations_exploring] = previous_session_flag
    response_body = { stored_blobs_amount: stored_blobs.size,
                      stored_blobs_size: represent_size(stored_blobs_size),
                      required_blobs_amount: required_blobs.size,
                      required_blobs_size: represent_size(required_blobs_size),
                      unused_blobs_amount: unused_blobs.size,
                      unused_blobs_size: represent_size(unused_blobs_size),
                      source_blobs: blobs_set.to_a.to_json
    }.to_json
    body response_body
  end

  def self.get_session
    @@current_session
  end

  error do
    "<h1>Error: #{env['sinatra.error']}</h1> <pre>#{env['sinatra.error'].backtrace.join("\n")}</pre>"
  end
end
