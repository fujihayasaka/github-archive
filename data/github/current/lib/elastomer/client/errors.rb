# typed: true
# frozen_string_literal: true

module ElastomerClient
  class Client
    # This error class is intended to be used for operations that affect multiple documents
    # in a single call like the `*_by_query` or reindex APIs which return a "failures"
    # array in the response body.
    # This is separate from the ElastomerClient::Client::Error class which parses
    # a single "error" field from the response body for single document operations.
    class MultiDocumentRequestError < ElastomerClient::Error
      include T::Sig

      RETRYABLE_ERROR_TYPES = T.let([
        # A search context could not be created to search for documents during the
        # current request because the maximum number of open search contexts
        # would be exceeded. This is a transient error that may succeed on a retry
        # if the number of open contexts drops below the configured maximum.
        TOO_MANY_SCROLL_CONTEXTS_ERROR_TYPE = "too_many_scroll_contexts_exception",

        # The requested document version is not the latest version. Retrying the
        # request may succeed after Elasticsearch's internal document version is updated.
        VERSION_CONFLICT_ENGINE_ERROR_TYPE = "version_conflict_engine_exception",
      ].freeze, T::Array[String])

      attr_reader :body, :failures, :root_causes

      sig { params(response: T::Hash[T.any(String, Symbol), T.untyped]).void }
      def initialize(response)
        response = response.deep_stringify_keys

        @body = T.let(response, T.nilable(T::Hash[String, T.untyped]))

        failure_causes = Array(response.fetch("failures", nil)).map { |failure| failure["cause"] }
        @failures = T.let(failure_causes, T::Array[T::Hash[String, T.untyped]])

        # If there are version conflicts, we add them to the failures list
        # so they are reported to observability tools and the error is marked as retryable.
        if (version_conflicts = response.fetch("version_conflicts", 0).to_i) > 0
          @failures << {
            "type" => VERSION_CONFLICT_ENGINE_ERROR_TYPE,
            "reason" => "#{version_conflicts} version conflicts reported"
          }
        end

        # Determine all unique root causes to the error
        @root_causes = T.let(parse_root_causes(@failures).uniq, T::Array[String])

        # The error is fatal if it has no retryable root causes
        @fatal = (@root_causes & RETRYABLE_ERROR_TYPES).empty?

        super(@failures.to_s)
      end

      sig { returns(T::Boolean) }
      def fatal?
        @fatal
      end

      sig { returns(T::Boolean) }
      def retry?
        !fatal?
      end

      private

      sig { params(failures: T::Array[T::Hash[String, T.untyped]]).returns(T::Array[String]) }
      def parse_root_causes(failures)
        return [] if failures.blank?

        failures.flat_map do |failure|
          next failure["type"] if failure["root_cause"].blank?

          root_causes = T.let(
            failure["root_cause"].is_a?(Hash) ? [failure["root_cause"]] : Array(failure["root_cause"]),
            T::Array[T::Hash[String, T.untyped]]
          )

          parse_root_causes(root_causes)
        end
      end
    end
  end
end
