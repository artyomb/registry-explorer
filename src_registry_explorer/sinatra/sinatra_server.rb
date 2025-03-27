#!/bin/env ruby
require 'sinatra/base'
require 'slim'
require 'rack/sassc'
require 'uri'
require 'net/http'
require 'cgi'
require_relative '../utils/file_utils'
require_relative '../utils/garbage_collection'

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
  get '/blobs-exploring',         &->() { slim :blobs_exploring }
  # get '/tag-exploring/*', &->() { slim :tag_exploring }
  get '/tag-exploring/*' do
    full_tag_path = params[:splat].first || ''
    slim :tag_exploring, locals: { full_tag_path: full_tag_path }
  end
  get '/image-exploring/*' do
    tag_image_path = params[:splat].first || '' # expect following url: /image-exploring/re/po/si/to/ry/tag_name/imgsha256
    slim :image_exploring, locals: { tag_image_path: tag_image_path }
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

  get '/file-in-archive/:sha256', &->() { slim :file_in_archive }
  get '/test', &->() { slim :test }

  # get '/file-in-archive/*/$path/*' do
  #   blob_sha256 = params[:splat].first
  #   file_path = '/' + params[:splat][1]

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
    return delete_index(image_path, image_sha256, false)
  end

  delete '/delete-tag/*' do
    path_data = params[:splat].first.split('/$sha256/')
    image_path = path_data[0]
    image_sha256 = path_data[1]
    return delete_index(image_path, image_sha256, true)
  end

  delete '/delete-non-current-images/*' do
    if $read_only_mode
      return [403, 'Registry is in read-only mode']
    end
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
        delete_index(url_image_path, sha256, false)
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

  delete '/perform-garbage-collection' do
    raise(StandardError, "You can't perform garbage collection as you boot your service in read-only mode") if $read_only_mode
    #
    if params[:with_history] == 'true'
      request_body = JSON.parse(request.body.read, symbolize_names: true)
      session = RegistryExplorerFront.get_session
      previous_session_flag = session[:attestations_exploring]
      session[:attestations_exploring] = true
      status, message = garbage_collect_with_history(request_body[:blobs])
      session[:attestations_exploring] = previous_session_flag
      [status, message]
    elsif params[:with_history] == 'false'
      request_body = JSON.parse(request.body.read, symbolize_names: true)
      session = RegistryExplorerFront.get_session
      previous_session_flag = session[:attestations_exploring]
      session[:attestations_exploring] = true
      status, message = garbage_collect_without_history(request_body[:blobs])
      session[:attestations_exploring] = previous_session_flag
      [status, message]
    end
  end

  def delete_index(image_path, image_sha256, is_current)
    if $read_only_mode
      return [403, 'Registry is in read-only mode']
    end
    request_url = "http://#{$hostname}#{$port.nil? ? '' : (':' + $port)}/v2/#{image_path}/manifests/sha256:#{image_sha256}"

    begin
      url = URI.parse(request_url)
      http = Net::HTTP.new(url.host, url.port)
      request = Net::HTTP::Delete.new(url.request_uri)
      error_message = $registry_host.nil? ? 'Registry host is not set' : ""
      if !error_message.empty?
        raise StandardError, error_message
      end
      request['Accept'] = CachesManager.find_node(image_sha256).node_type
      response = http.request(request)
      if response.code.to_i / 100 == 2
        message = "#{is_current ? 'Tag' : 'Image'} by sha256:#{image_sha256} deleted successfully"
        puts message
        return message
      else
        message = "Error deleting #{is_current ? 'tag' : 'image'} by sha256:#{image_sha256} from #{image_path}. Registry message: #{response.message}"
        puts message
        raise StandardError, message
      end
    rescue StandardError => e
      message = "Error deleting image #{image_sha256} from #{image_path}: #{e.message}"
      puts message
      status 400
      raise StandardError, message
    end
  end

  def self.get_session
    @@current_session
  end

  error do
    "<h1>Error: #{env['sinatra.error']}</h1> <pre>#{env['sinatra.error'].backtrace.join("\n")}</pre>"
  end
end
