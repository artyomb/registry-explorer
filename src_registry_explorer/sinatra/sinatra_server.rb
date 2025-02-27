#!/bin/env ruby
require 'sinatra/base'
require 'slim'
require 'rack/sassc'
require 'cgi'
require_relative '../utils/file_utils'

class RegistryExplorerFront < Sinatra::Base
  use Rack::SassC, css_location: "#{__dir__}/../public/css", scss_location: "#{__dir__}/../css",
      create_map_file: true, syntax: :sass, check: true
  use Rack::Static, urls: %w[/css /js], root: "#{__dir__}/public/", cascade: true

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


  def self.get_session
    @@current_session
  end

  error do
    "<h1>Error: #{env['sinatra.error']}</h1> <pre>#{env['sinatra.error'].backtrace.join("\n")}</pre>"
  end
end
