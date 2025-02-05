#!/bin/env ruby
require 'sinatra/base'
require 'slim'
require 'rack/sassc'

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

  get '/file-in-archive/*/$path/*' do
    blob_sha256 = params[:splat].first
    file_path = params[:splat][1..]
    "<style>span {color:blue;}</style><span>Blob SHA256: #{blob_sha256}</span><br><span>File path: #{file_path}</span>"
  end
  get '/healthcheck', &-> { 'Healthy' }

  error do
    "<h1>Error: #{env['sinatra.error']}</h1> <pre>#{env['sinatra.error'].backtrace.join("\n")}</pre>"
  end
end
