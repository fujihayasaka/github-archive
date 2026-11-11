# typed: false
# frozen_string_literal: true

module Api
  # Shared behaviour between `Api::SerializerOptions` and
  # `Api::Serializer::LegacySearchOptions`
  module SerializerOptionsMimeTypes
    # Check `Accept` headers against a given semantic version.
    #
    # semantic_version - Version String (e.g., 'beta', 'v3', 'v4').
    #
    # Example:
    #
    #     options.accepts_semantic_version?("night-shift")
    #
    # Returns true if the `Accept` headers explicitly reference the given
    #   version. Returns true if the given version is the default version, and
    #   the headers fail to reference some other (non-default) version.
    #   Returns false otherwise.
    def accepts_semantic_version?(semantic_version)
      accepted_media_types.accepts_semantic_version?(semantic_version)
    end

    def accepted_media_types
      Api::AcceptedMediaTypes.new(accept_mime_types)
    end

    # Check `Accept` headers for v3 support.
    #
    # Returns a Boolean.
    def accepts_v3?
      accepts_semantic_version?(:v3)
    end

    # Do the `Accept` headers indicate that the response should use the beta
    # media type?
    #
    # Only return true if beta is present and there are no newer versions
    # (including previews) available.
    #
    # Returns a Boolean.
    def wants_beta_media_type?
      # TODO Enhance this logic to respect the quality factor specified in the
      # `Accept` header. Only return true if the quality factors give
      # preference to the beta media type.
      # See http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html.
      accepts_semantic_version?(:beta) && !accepts_v3?
    end

    # Check Accept headers for presence of the given parameter.
    #
    # param - A String parameter name (e.g., 'raw', 'text-match', etc.).
    #
    # Returns a Boolean.
    def accepts_param?(param)
      Array(mime_params).include?(param)
    end

    # Determine whether the currently selected API version has
    # a specific changeset activated.
    #
    # changeset_name - The name of the changeset as a Symbol or String.
    #
    # Returns a Boolean.
    def changeset_active?(changeset_name)
      !!api_version&.changeset_active?(changeset_name)
    end
  end
end
