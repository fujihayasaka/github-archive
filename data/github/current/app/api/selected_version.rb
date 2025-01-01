# typed: true
# frozen_string_literal: true

module Api
  # Represents a Selected API version.
  #
  # Used as a container for API version specific information.
  # Gets stored in the rack environment hash (key: HTTP_GITHUB_API_VERSION)
  # Gets decomposed and used to set the API version and reason on the outgoing response.
  class SelectedVersion

    NEXT_VERSION = "next"
    ENV_REQUESTED_API_VERSION = "HTTP_X_GITHUB_API_VERSION"
    HTTP_HEADER_API_REQUESTED_VERSION = "X-GitHub-API-Version"
    HTTP_HEADER_API_SELECTED_VERSION = "X-GitHub-API-Version-Selected"
    HTTP_HEADER_API_SELECTED_VERSION_REASON = "X-GitHub-API-Version-Selected-Reason"

    REASON_DEFAULT = "default"
    REASON_REQUEST_HEADER = "request_header"
    REASON_PINNED = "pinned"
    REASON_SKIPPED = "skipped"
    REASON_INVALID = "invalid"
    REASON_UNAVAILABLE = "unavailable"

    def initialize(requested_version, version, reason)
      @requested_version = requested_version
      @version = version
      @reason = reason
    end

    # this is the version that the client requested
    def requested_version
      @requested_version
    end

    # this is the version that the middleware selected
    def version
      @version
    end

    # this is why the middleware selected the version
    def reason
      @reason
    end

    def skipped?
      @reason == REASON_SKIPPED
    end

    def pinned?
      @reason == REASON_PINNED
    end

    def invalid?
      @reason == REASON_INVALID
    end

    def default?
      @reason == REASON_DEFAULT
    end

    def request_header?
      @reason == REASON_REQUEST_HEADER
    end

    # Determine if a given changeset is active in the selected API version.
    #
    # @param changeset_name [Symbol, String] the ID of the changeset
    #
    # @return [Boolean]
    def changeset_active?(changeset_name)
      OpenApi::Description::Changeset.schedule.changeset_active?(
        release: OpenApi::Description::Release.current(include_unpublished: true),
        version: @version,
        changeset: changeset_name.to_s
      )
    end
  end
end
