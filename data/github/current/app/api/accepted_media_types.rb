# typed: false
# frozen_string_literal: true

module Api
  # Represents the collection of media types that a request accepts, as
  # specified via the `Accept` headers.
  class AcceptedMediaTypes
    attr_reader :media_type_strings

    SINATRA_DEFAULT_MEDIA_TYPE = "*/*"

    # Public: Initialize an AcceptedMediaTypes.
    #
    # media_type_strings - String or array of media type Strings specified via the
    #                      `Accept` headers in a request.
    def initialize(media_type_strings, request_path = nil)
      @request_path = request_path
      @media_type_strings = media_type_strings.is_a?(String) ? media_type_strings.split(",") : Array(media_type_strings)
    end

    # Public: Determine whether the media types explicitly or implicitly accept
    # the given semantic version.
    #
    # semantic_version - String API version name (e.g., 'beta', 'v3', 'v4').
    #
    # Returns true if the media types explicitly reference the given semantic version.
    #   Returns true if the given semantic version is the default semantic version, and the media
    #   types to reference some other (non-default) semantic version. Returns false
    #   otherwise.
    def accepts_semantic_version?(semantic_version)
      return true if explicitly_accepts_semantic_version?(semantic_version)

      default_semantic_version?(semantic_version) && implicitly_accepts_default_semantic_version?
    end

    def contains_preview?
      media_type_strings.any? do |media_type_string|
        media_type = Api::MediaType.new(media_type_string)
        media_type.preview_semantic_version?
      end
    end

    # Public: Determine whether the media types explicitly reference the given
    # semantic version.
    #
    # semantic_version - String API version name (e.g., 'beta', 'v3', 'v4').
    #
    # Returns true if at least one of the media types explicitly references the
    #   given semantic version. Returns false otherwise.
    def explicitly_accepts_semantic_version?(semantic_version)
      media_type_strings.any? do |media_type_string|
        media_type = Api::MediaType.new(media_type_string)
        media_type.explicit_api_semantic_version?(semantic_version)
      end
    end

    # Public: Determine whether the media types implicitly accept the default
    # semantic version. If the media types fail to reference some other (non-default)
    # version, then the request implicitly gets the default semantic version.
    #
    # Returns a Boolean.
    def implicitly_accepts_default_semantic_version?
      contains_preview? || Api::MediaType.non_default_semantic_versions.none? { |v| explicitly_accepts_semantic_version?(v) }
    end

    def api
      api_media_types.find { |m| m.api? }
    end

    def semantic_version(semantic_version)
      api_media_types.find { |m| m.api_semantic_version?(semantic_version) }
    end

    def semantic_versions
      api_media_types.map(&:version).compact
    end

    def api_semantic_versions
      api_media_types.select { |m| m.respond_to?(:api_semantic_version) }.map(&:api_semantic_version)
    end

    # application/json and Sinatra's defaults are not GitHub media types, and don't have `to_http_header`
    def to_http_header
      api_media_types.select { |m| m.respond_to?(:to_http_header) }.map(&:to_http_header).join(", ")
    end

    def to_api_semantic_version
      api_semantic_versions.join(", ")
    end

    def map(&block)
      api_media_types.map(&block)
    end

    def reject(&block)
      api_media_types.reject(&block)
    end

    def empty?
      api_media_types.empty?
    end

    def acceptable?
      !empty? && api
    end

    def semantic_version?(semantic_version)
      api_media_types.any? { |m| m.version == semantic_version }
    end

    def api_semantic_version?(semantic_version)
      api_media_types.any? { |m| m.api_semantic_version?(semantic_version) }
    end

    def api_param?(param)
      api_media_types.any? { |m| m.api_param?(param) }
    end

    def preview_version?
      api_media_types.any? { |m| m.preview_semantic_version? }
    end

    def json?
      api_media_types.any? { |m| m.json? }
    end

    def v3?
      api_media_types.all? { |_m| api_semantic_version?(:v3) }
    end

    def api_params
      api_media_types.map { |m| m.api_params }
    end

    def sub_type
      v3&.sub_type
    end

    def to_s
      @media_type_strings.join(",")
    end

    private

    def v3
      api_media_types.find { |m| m.v3? }
    end

    # Internal: Determine whether the given semantic version is the current default.
    #
    # semantic_version - String or Symbol version name.
    #
    # Returns a Boolean.
    def default_semantic_version?(semantic_version)
      semantic_version.to_sym == Api::MediaType::DefaultSemanticVersion
    end

    # Internal: Get the GitHub-accepted media types from the list of accepted
    # media types.
    #
    # Returns an array of Api::MediaType.
    def api_media_types
      return @api_media_types if defined?(@api_media_types)
      @api_media_types = []
      api_semantic_version = Api::MediaType.identify_api_semantic_version(@request_path)
      # the raw media type string can include duplicate values because it's a user-provided
      # value, so we remove those duplicates with uniq and sort as well
      media_type_strings.uniq.sort.each do |media_type_string|
        parsed = Api::MediaType.new(media_type_string.strip, api_semantic_version)
        parsed.preview_semantic_version?
        if @api_media_types.empty? || parsed.preview_semantic_version? || (parsed.api? && !@api_media_types.any? { |m| m.api? })
          @api_media_types << parsed
        else
          # merge API params into last media type, per RFC
          @api_media_types.last.api_params.merge(parsed.api_params)
        end
      end

      if @api_media_types.empty? || @api_media_types.join(",") == SINATRA_DEFAULT_MEDIA_TYPE
        @api_media_types = [Api::MediaType.semantic_default(api_semantic_version)]
      else
        @api_media_types
      end
    end
  end
end
