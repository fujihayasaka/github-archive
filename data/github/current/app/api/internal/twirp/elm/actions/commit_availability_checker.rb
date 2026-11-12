# typed: strict
# frozen_string_literal: true

require "set"

module Api::Internal::Twirp::Elm
  module Actions
    # Determines which requested OIDs currently resolve to commit objects.
    #
    # Missing and wrong-type objects are considered unavailable. Operational
    # failures and malformed Spokes responses are raised.
    class CommitAvailabilityChecker
      # ReadObjects accepts at most 1,000 OIDs per request.
      READ_OBJECTS_BATCH_SIZE = 1_000

      sig { params(repository: ::Repositories::IRepository).void }
      def initialize(repository:)
        @repository = T.let(T.cast(repository, ::Repository), ::Repository)
      end

      # Returns the normalized OIDs that currently resolve to commit objects.
      sig { params(commit_oids: T::Array[String]).returns(T::Set[String]) }
      def available_oids(commit_oids)
        normalized_oids = commit_oids
          .map { |commit_oid| commit_oid.downcase }
          .uniq

        available_oids = T.let(::Set.new, T::Set[String])

        normalized_oids.each_slice(READ_OBJECTS_BATCH_SIZE) do |batch|
          response = @repository.spokes_api.read_objects(
            oids: batch,
            types: Array.new(batch.size, "commit"),
            qos: :QUALITY_OF_SERVICE_NO_DELAY
          )

          validate_read_objects_response_size!(batch, response.objects)

          batch.each_with_index do |requested_oid, index|
            result = response.objects[index]

            if result&.commit_object != nil && result.object&.type == :TYPE_COMMIT
              available_oids.add(requested_oid)
              next
            end

            handle_commit_lookup_error!(requested_oid, result)
          end
        end

        available_oids
      end

      private

      # ReadObjects results are positionally associated with request selectors.
      sig do
        params(
          requested_oids: T::Array[String],
          results: T.untyped
        ).void
      end
      def validate_read_objects_response_size!(requested_oids, results)
        return if results.size == requested_oids.size

        raise SpokesAPI::Error,
          "ReadObjects returned #{results.size} objects for #{requested_oids.size} requested OIDs"
      end

      sig do
        params(
          requested_oid: String,
          result: T.untyped
        ).void
      end
      def handle_commit_lookup_error!(requested_oid, result)
        if result.nil?
          raise SpokesAPI::Error,
            "ReadObjects returned an empty result for #{requested_oid}"
        end

        error = result.error_object
        if error.nil?
          raise SpokesAPI::Error,
            "ReadObjects returned neither a commit nor an error for #{requested_oid}"
        end

        case error.error_reason
        when :ERROR_REASON_MISSING,
             :ERROR_REASON_TYPE_MISMATCH
          nil
        when :ERROR_REASON_AMBIGUOUS,
             :ERROR_REASON_INVALID,
             :ERROR_REASON_TOO_LARGE
          raise GitRPC::InvalidObject.new(error.error)
        else
          raise GitRPC::Error.new(error.error)
        end
      end
    end
  end
end
