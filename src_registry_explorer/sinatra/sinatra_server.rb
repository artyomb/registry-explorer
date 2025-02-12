#!/bin/env ruby
require 'sinatra/base'
require 'slim'
require 'rack/sassc'
require_relative '../utils/file_utils'

class RegistryExplorerFront < Sinatra::Base
  use Rack::SassC, css_location: "#{__dir__}/../public/css", scss_location: "#{__dir__}/../css",
      create_map_file: true, syntax: :sass, check: true
  use Rack::Static, urls: %w[/css /js], root: "#{__dir__}/public/", cascade: true

  set :root, '.' #File.dirname(__FILE__)
  get '/',         &->() { slim :index }
  get '/index',         &->() { slim :index }
  # get '/tag-exploring/*', &->() { slim :tag_exploring }
  get '/tag-exploring/*' do
    full_tag_path = params[:splat].first || ''
    slim :tag_exploring, locals: { full_tag_path: full_tag_path }
  end
  get '/json/:sha256', &->() { slim :json }
  get '/tar-gz/:sha256', &->() { slim :targz }
  get '/file-in-archive/:sha256', &->() { slim :file_in_archive }

  # get '/file-in-archive/*/$path/*' do
  #   blob_sha256 = params[:splat].first
  #   file_path = '/' + params[:splat][1]
  get '/file-in-archive/*' do
    path_data = params[:splat].first.split('/$path/')
    blob_sha256 = path_data[0]
    file_path = path_data[1]
    "<pre style='background-color: #e4e4e4; margin-bottom: 0; height: -webkit-fill-available;'>#{extract_file_content_from_archive_by_path(blob_sha256, file_path)}</pre>"
  end
  get '/healthcheck', &-> { 'Healthy' }

  error do
    "<h1>Error: #{env['sinatra.error']}</h1> <pre>#{env['sinatra.error'].backtrace.join("\n")}</pre>"
  end
end
