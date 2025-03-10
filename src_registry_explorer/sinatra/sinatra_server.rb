#!/bin/env ruby
require 'sinatra/base'
require 'slim'
require 'rack/sassc'
require 'uri'
require 'net/http'
require 'cgi'
require_relative '../utils/file_utils'

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
  # get '/tag-exploring/*', &->() { slim :tag_exploring }
  get '/tag-exploring/*' do
    full_tag_path = params[:splat].first || ''
    slim :tag_exploring, locals: { full_tag_path: full_tag_path }
  end
  get '/image-exploring/*' do
    tag_image_path = params[:splat].first || '' # expect following url: /image-exploring/re/po/si/to/ry/tag_name/imgsha256
    slim :image_exploring, locals: { tag_image_path: tag_image_path }
  end
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

  def delete_index(image_path, image_sha256, is_current)
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
      # request['Accept'] = 'application/vnd.docker.distribution.manifest.v2+json'
      response = http.request(request)
      if response.code.to_i / 100 == 2
        message = "#{is_current ? 'Tag' : 'Image'} by sha256:#{image_sha256} deleted successfully"
        puts message
        # CachesManager.execute_refresh_pipeline
        return message
      else
        message = "Error deleting #{is_current ? 'tag' : 'image'} by sha256:#{image_sha256} from #{image_path}. Registry message: #{response.message}"
        puts message
        # CachesManager.execute_refresh_pipeline
        return message
      end
    rescue StandardError => e
      message = "Error deleting image #{image_sha256} from #{image_path}: #{e.message}"
      puts message
      # CachesManager.execute_refresh_pipeline
      status 400
      return message
    end
  end

  def self.get_session
    @@current_session
  end

  error do
    "<h1>Error: #{env['sinatra.error']}</h1> <pre>#{env['sinatra.error'].backtrace.join("\n")}</pre>"
  end
end
