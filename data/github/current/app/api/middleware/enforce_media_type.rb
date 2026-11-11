# typed: true
# frozen_string_literal: true

class Api::Middleware::EnforceMediaType
  ContentType = "CONTENT_TYPE".freeze
  ContentMediaType = "github.content_media_type".freeze

  # Gets the current MediaType from Content-Type.  Assumes #call has been run.
  #
  # env - A Hash Rack environment.
  #
  # Returns an Api::MediaType.
  def self.current(env)
    env[ContentMediaType]
  end

  def initialize(app, skip: [])
    @app = app
    @skip = Set.new(skip)
  end

  # Ensures that the default Content-Type is valid for the API.  Specifically
  # reject form encodings.  Eventually I'd like to remove the other media-type
  # related stuff here, but I like taking advangate of `request.accept` and
  # `#unacceptable_media_types?` from the Sinatra apps.
  def call(env)
    GitHub.tracer.in_span("api.middleware", kind: :internal, attributes: {
      "code.namespace" => "EnforceMediaType"
    }) do |_span|
      return @app.call(env) if @skip.include?(env["github.api.route"])

      ctype = env[ContentType]
      ctype = nil if ctype && ctype =~ /form/i

      api_semantic_version = Api::MediaType.identify_api_semantic_version(env["PATH_INFO"])
      media = if ctype.blank?
        Api::MediaType.semantic_default(api_semantic_version)
      else
        Api::MediaType.new(ctype, api_semantic_version)
      end

      env[ContentType] = media.to_s
      env[ContentMediaType] = media
      @app.call(env)
    end
  end
end
