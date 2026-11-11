# typed: true
# frozen_string_literal: true

require "set"
require "github/pi_media_type"

module Api
  # Represents a parsed GitHub media type.
  class MediaType < GitHub::PiMediaType
    # [DEPRECATED] - Semantic versions supplanted by Calendar-based API versioning
    V3 = DefaultSemanticVersion = :v3
    V4 = :v4
    SemanticVersions = Set.new(%w(
      beta
      v4
      v3
    )) + Rest::Previews.media_versions

    def self.semantic_default(api_semantic_version = V3)
      new("application/vnd.github.#{api_semantic_version}+json", api_semantic_version)
    end

    # Provide the list of valid API semantic versions, excluding the default semantic versions.
    #
    # Returns an Enumerable of Strings.
    def self.non_default_semantic_versions
      SemanticVersions - [V3.to_s, V4.to_s]
    end

    def self.identify_api_semantic_version(path)
      path == "/graphql" ? V4 : V3
    end

    def initialize(type, api_semantic_version = V3)
      super(type)
      @implicit_api_semantic_version = api_semantic_version
    end

    def api?
      @string =~ /(application|text|\*)\/(json|\*)/i || vendor =~ /^github/i
    end

    def json?
      suffix == "json"
    end

    # Provide the media type's derived Semantic API version. If the media type does not
    # explicitly declare a valid GitHub Semantic API version, we use the default version.
    #
    # Returns a String.
    def api_semantic_version
      @api_semantic_version ||= parse_api_options(:semantic_version)
    end

    # Determine whether the media type's derived semantic version matches the given
    # semantic version.
    #
    # semantic_version - String or Symbol semantic API version name (e.g., 'beta', 'v3', 'v4').
    #
    # Returns a Boolean.
    def api_semantic_version?(semantic_version)
      api_semantic_version == semantic_version.to_sym
    end

    # Determine whether the media type explicitly declares the given semantic version.
    #
    # semantic_version - String or Symbol API version name (e.g., 'beta', 'v3', 'v4').
    #
    # Examples
    #
    #   MediaType.new('application/json').explicit_api_semantic_version?('v3')
    #   # => false
    #
    #   MediaType.new('application/vnd.github').explicit_api_semantic_version?('v3')
    #   # => false
    #
    #   MediaType.new('application/vnd.github.beta').explicit_api_semantic_version?('v3')
    #   # => false
    #
    #   MediaType.new('application/vnd.github.v3').explicit_api_semantic_version?('v3')
    #   # => true
    #
    # Returns a Boolean.
    def explicit_api_semantic_version?(semantic_version)
      @string =~ /\Aapplication\/vnd.github([-\w]*)?.#{semantic_version}/
    end

    def preview_semantic_version?
      api_semantic_version.to_s.end_with?("-preview")
    end

    def v3?
      api_semantic_version?(V3)
    end

    def v4?
      api_semantic_version?(V4)
    end

    def api_params
      @api_params ||= parse_api_options(:params)
    end

    def api_param?(param)
      param && api_params.include?(param.to_sym)
    end

    # [DEPRECATED] formats header using semantic versioning
    def to_http_header
      return "unknown" unless api?
      header = "github.#{api_semantic_version}"
      header << "; param=%s" % api_params.to_a.join(".") if !api_params.empty?
      header << "; format=%s" % suffix unless suffix.empty?
      header
    end

    def parse_api_options(return_suffix)
      @api_semantic_version = @implicit_api_semantic_version
      @api_params = Set.new

      if pieces = version && version.split(".")
        if SemanticVersions.include?(pieces[0])
          @api_semantic_version = pieces.shift.to_sym
        end

        pieces.each do |param|
          @api_params << param.to_sym
        end
      end

      instance_variable_get "@api_#{return_suffix}"
    end
  end
end
