#!/usr/bin/env ruby
require_relative 'logging'
require_relative 'otlp'
otel_initialize
require_relative 'helpers'
require_relative 'config.rb'
require_relative 'sinatra/sinatra_server'


run RegistryExplorerFront

# PATCH: /home/user/.rbenv/versions/3.1.2/bin/bundle
# Dir.chdir File.dirname(ARGV.last) if ARGV.last =~ /\.ru/


# RACK_ENV=production bundle exec rackup -o 0.0.0.0 -p 7000 -s falcon
