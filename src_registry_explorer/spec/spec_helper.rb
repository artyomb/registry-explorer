# frozen_string_literal: true
$VERBOSE = nil

ENV['CONSOLE_LEVEL'] = 'error' # 'all'
ENV['CONSOLE_OUTPUT'] = 'XTerm' # JSON,Text,XTerm,Default
TRACE_METHODS = true

ENV['OTEL_LOG_LEVEL'] = 'error'
ENV['OTEL_TRACES_EXPORTER'] = '' #otlp'
ENV['OTEL_EXPORTER_OTLP_ENDPOINT'] = '' # http://swarm.next/apm/otlp/'
ENV['STACK_NAME'] = 'Rspec'
ENV['STACK_SERVICE_NAME'] = 'ARINC_Rest'
ENV['DB_URL'] = 'sqlite::memory:'
require 'rspec-benchmark'
require 'rack/test'
require 'async/rspec'

require 'simplecov'
SimpleCov.start
# require 'simplecov-cobertura'
# SimpleCov.formatter = SimpleCov::Formatter::CoberturaFormatter

require 'rbase/rack_helpers'
$app = nil
def rack_run(&) = $app = rack_build(&)
# FOR NOW SKIP UNTIL HAVING ABILITY TO TEST SQLITE WITH POSTGIS FUNCTIONS
# load "#{__dir__}/../config.ru"

module Rack::Test::JHelpers
  def app = $app

  def do_j(resp)
    expect(resp.status.to_i / 100).to eq(2), resp.body
    expect(resp.headers['content-type']).to eq 'application/json'
    JSON.parse(resp.body, symbolize_names: true).tap do |j|
      yield(j) if block_given?
    end
  end

  def get_j(url, &) = do_j(get(url), &)
  def post_j(url, params, &) = do_j(post(url, params.to_json, 'CONTENT_TYPE' => 'application/json'), &)
  def post_file(url, file_extention, params = {})
    params.transform_values! { _1.respond_to?(:eof?) ? Rack::Test::UploadedFile.new(_1, original_filename: "filename#{file_extention}") : _1 }
    post url, params
    yield(JSON.parse(last_response.body, symbolize_names: true)) if block_given?
  end
end

RSpec.configure do |config|
  config.include Rack::Test::Methods
  config.include Rack::Test::JHelpers
  config.include RSpec::Benchmark::Matchers
  config.include_context Async::RSpec::Reactor
end