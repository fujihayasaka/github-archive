# typed: strict
# frozen_string_literal: true

module PullRequests
  module GitSystems
    module BatchWriteRefs
      # Batching class for doing ref updates that conform to branch rules/protections.
      class Service
        class Result < T::Struct
          # The requests that were operated upon. Each request has a resulting `state` object describing the outcome.
          const :requests, T::Array[Request]

          # If an exception was raised during exceution, it's available here as well as on the affected requests.
          const :exception, T.nilable(Exception)
        end

        MAX_ATTEMPTS = 3

        sig { params(repository: Repository, actor: User, priority: Symbol).void }
        def initialize(repository:, actor:, priority: :low)
          @repository = repository
          @actor = actor
          @priority = priority

          @requests = T.let({}, T::Hash[String, Request])
        end

        sig { params(ref_name: String, before_oid: T.nilable(String), after_oid: String).void }
        def add(ref_name:, before_oid:, after_oid:)
          @requests[ref_name] = Request.new(ref_name:, before_oid:, after_oid:)
        end

        sig { returns(Result) }
        def call
          attempts = 0
          requests = @requests.values

          begin
            @repository.batch_write_refs(
              @actor,
              requests.map(&:to_batch_write_refs_tuple),
              no_custom_hooks: requests.none?(&:public_refspec?),
              post_receive: requests.any?(&:public_refspec?),
              priority: @priority,
            )

            # Upon success, mark every pending request as successful.
            requests.each(&:mark_successful!)
          rescue => exception # rubocop:disable Lint/RescueException
            case error = GitSystems.classify_exception(exception)
            when GitSystems::Errors::Outage, GitSystems::Errors::Timeout
              if attempts < MAX_ATTEMPTS
                attempts += 1
                retry
              end
            end

            requests.each { _1.mark_failed!(message: exception.message, reason: FailureReason::RefUpdateFailed, exception:) }
          end

          Result.new(requests: requests, exception:)
        end
      end
    end
  end
end
