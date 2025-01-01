# typed: strict
# frozen_string_literal: true

require_relative "../config/environment"
require "github/memoizer"
require "uri"

class Routemapper
  include GitHub::Memoizer

  sig { params(request_method: String, url: T.any(String, URI::Generic)).void }
  def initialize(request_method, url)
    @request_method = request_method
    url = URI.parse(url) if url.is_a?(String)

    raise ArgumentError, "URL must have a path" unless url.path
    if url.host&.start_with?("api.") || url.path&.match?(/\A\/?api\//)
      raise ArgumentError, "Sorry, API routes are not currently supported"
    end
    @path = T.let(T.must(url.path), String)
  end

  sig { params(output: T.any(IO, StringIO)).void }
  def report(output: $stdout)
    output.puts "Controller: #{controller_class.name}"
    output.puts "Action: #{action_method.name}"
    if params.any?
      output.puts "Parameters: #{params.map { |k, v| "#{k}=#{v.inspect}" }.join(", ")}"
    end
    location = action_method.source_location
    output.puts "\nSource location: #{location.join(":")}" if location
  end

  private

  sig { returns(String) }
  attr_reader :request_method, :path

  sig { returns(T::Hash[Symbol, String]) }
  memoize def recognition
    route_set = Rails.application.routes
    route_set.eager_load!
    route_set.recognize_path(path, method: request_method)
  end

  sig { returns(T.class_of(ApplicationController)) }
  memoize def controller_class
    # Raises a MissingController exception if the controller can't be found.
    ActionDispatch::Request.empty.controller_class_for(recognition[:controller])
  end

  sig { returns(UnboundMethod) }
  memoize def action_method
    controller_class.instance_method(recognition.fetch(:action, "index"))
  end

  sig { returns(T::Hash[Symbol, String]) }
  def params
    recognition.without(:controller, :action, :format)
  end
end
