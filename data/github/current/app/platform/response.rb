# typed: true
# frozen_string_literal: true

module Platform
  class Response
    # A response must define an instrumenter that knows how to serialize
    # response data to both Hydro and Datadog
    attr_reader :instrumenter

    def extensions
      {}
    end

    def data
      nil
    end

    def errors
      []
    end

    def scrubbed_query_string
      nil
    end

    def to_plain_h
      hash = {}
      hash["data"] = data if data || errors.empty?
      hash["errors"] = errors if errors.any?
      hash["extensions"] = extensions if extensions.any?
      hash
    end

    def to_h
      to_plain_h.with_indifferent_access
    end

    def to_hydro!
      instrumenter.to_graphql_query_event
    end

    # Public: Constructs the hash response, taking care not to provide keys that
    #         don't exist.
    #
    # Returns a string.
    def to_json(*options)
      to_h.to_json(*options)
    end

    # Public: Determines if a response is totally successful.
    #
    # Returns a boolean.
    def success?
      data.present? && errors.empty?
    end

    # Public: Determines if a response succeeded, but contains errors.
    #
    # Returns a boolean.
    def partial_success?
      data.present? && !errors.empty?
    end

    # Public: Determines if a response failed.
    #
    # Returns a boolean.
    def failure?
      errors.present?
    end
  end
end
