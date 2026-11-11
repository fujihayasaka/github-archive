# typed: strict
# frozen_string_literal: true

module Repositories
  class Domain
    class MergeTrees < GH::Domain::Base
      module State
        extend T::Helpers
        include Kernel

        sealed!

        class Unmergeable < T::Struct
          include State
        end

        class AlreadyMerged < T::Struct
          include State
        end

        class Mergeable < T::Struct
          include State

          const :tree_oid, String
        end

        class Conflict < T::Struct
          include State

          const :metadata, T.nilable(T::Hash[T.untyped, T.untyped])
        end
      end

      # Given two trees, this will check what the state of merging those trees will be. The dry_run method will not
      # persist the objects in the repository after the merge. This will allow us to use this when we only want
      # to check mergeability without having to use the generated oid of the merge.
      sig do
        params(
          repository: IRepository,
          base_oid: String,
          head_oid: String,
          base_repo_id: T.nilable(Integer),
          head_repo_id: T.nilable(Integer),
          priority: Symbol,
        ).returns(T.any(
          GH::Result[State],
          GH::Result::Error[String],
          GH::Result::Error::NotFound[NilClass],
          GH::Result::Error::Argument[String],
          GH::Result::Error::ServiceRateLimited[String],
          GH::Result::Error::ServiceUnreachable[String],
        ))
        .checked(:always)
        .on_failure(:raise)
      end
      def dry_run(repository:, base_oid:, head_oid:, base_repo_id: nil, head_repo_id: nil, priority: :low)
        qos = determine_quality_of_service(priority:)
        process(repository:, base_oid:, head_oid:, mergeability_only: true, include_conflict_details: true, qos:, base_repo_id:, head_repo_id:)
      end

      # Given two trees, this will check what the state of merging those trees will be. The run method will
      # persist the objects in the repository after the merge, so we can use it after the call.
      sig do
        params(
          repository: IRepository,
          base_oid: String,
          head_oid: String,
          base_repo_id: T.nilable(Integer),
          head_repo_id: T.nilable(Integer),
          priority: Symbol,
        ).returns(T.any(
          GH::Result[State],
          GH::Result::Error[String],
          GH::Result::Error::NotFound[NilClass],
          GH::Result::Error::Argument[String],
          GH::Result::Error::ServiceRateLimited[String],
          GH::Result::Error::ServiceUnreachable[String],
        ))
        .checked(:always)
        .on_failure(:raise)
      end
      def run(repository:, base_oid:, head_oid:, base_repo_id: nil, head_repo_id: nil, priority: :low)
        qos = determine_quality_of_service(priority:)
        process(repository:, base_oid:, head_oid:, mergeability_only: false, include_conflict_details: true, qos:, base_repo_id:, head_repo_id:)
      end

      private

      sig do
        params(
          repository: IRepository,
          base_oid: String,
          head_oid: String,
          mergeability_only: T::Boolean,
          include_conflict_details: T::Boolean,
          qos: Symbol,
          base_repo_id: T.nilable(Integer),
          head_repo_id: T.nilable(Integer),
        ).returns(T.any(
          GH::Result[State],
          GH::Result::Error[String],
          GH::Result::Error::NotFound[NilClass],
          GH::Result::Error::Argument[String],
          GH::Result::Error::ServiceRateLimited[String],
          GH::Result::Error::ServiceUnreachable[String],
        ))
        .checked(:always)
        .on_failure(:raise)
      end
      def process(repository:, base_oid:, head_oid:, mergeability_only:, include_conflict_details:, qos:, base_repo_id:, head_repo_id:)  # rubocop:disable Metrics/MethodLength
        repository = T.cast(repository, Repository) # rubocop:todo GitHub/AvoidCast
        log_error = T.let(false, T::Boolean)
        result_state = :argument_error

        return GH::Result::Error::Argument.new("invalid base_oid") if invalid_oid?(base_oid)
        return GH::Result::Error::Argument.new("invalid head_oid") if invalid_oid?(head_oid)

        begin
          response = if mergeability_only
            # we don't need a transaction here since we will not be writing any objects.
            repository.spokes_api.merge_trees(
              base_oid:,
              head_oid:,
              base_repo_id:,
              head_repo_id:,
              mergeability_only:,
              include_conflict_details:,
              qos:,
            )
          else
            repository.spokes_api.with_transaction do
              repository.spokes_api.merge_trees(
                base_oid:,
                head_oid:,
                base_repo_id:,
                head_repo_id:,
                mergeability_only:,
                include_conflict_details:,
                qos:,
              )
            end
          end
        rescue SpokesAPI::NotFound => exception
          result_state = :not_found
          log_error = true
          return GH::Result::Error::NotFound.new(exception.message)
        rescue SpokesAPI::ResourceExhausted => exception
          result_state = :rate_limited
          log_error = true
          return GH::Result::Error::ServiceRateLimited.new(exception.message)
        rescue SpokesAPI::TwirpServerError, SpokesAPI::TimedOut, SpokesAPI::Canceled, SpokesAPI::TwirpConnectionError => exception
          result_state = :unreachable
          log_error = true
          return GH::Result::Error::ServiceUnreachable.new(exception.message)
        end

        state = case response.merge_status
        when :STATUS_SUCCESS
          result_state = :success
          State::Mergeable.new(tree_oid: response.oid.id)
        when :STATUS_MERGE_CONFLICT
          result_state = :merge_conflict
          State::Conflict.new(metadata: response.conflicts.to_h)
        when :STATUS_ALREADY_MERGED
          result_state = :already_merged
          State::AlreadyMerged.new
        else
          result_state = :unmergeable
          State::Unmergeable.new
        end

        GH::Result::Ok.new(state)
      ensure
        tags = ["state:#{result_state}", "dry_run:#{mergeability_only}", "cross_repo:#{base_repo_id != head_repo_id}"]
        GitHub.dogstats.increment("repository.domain.merge_trees.process", tags: tags)

        if log_error
          GitHub.logger.info("Call to Repositories::Domain::MergeTree",
            "gh.repo.id": repository.id,
            "dry_run": mergeability_only,
            "base_oid": base_oid,
            "head_oid": head_oid,
            "qos": qos,
            "base_repo_id": base_repo_id,
            "head_repo_id": head_repo_id,
            "caller_stack":  caller_locations.take(80).map { _1.label },
            "run_result": state
          )
        end
      end

      sig { params(oid: String).returns(T::Boolean) }
      def invalid_oid?(oid)
        !GitRPC::Util.valid_full_oid?(oid) || !!GitRPC::Util.null_oid?(oid)
      end

      sig { params(priority: Symbol).returns(Symbol) }
      def determine_quality_of_service(priority:)
        case priority
        when :high
          :QUALITY_OF_SERVICE_NO_DELAY
        when :medium
          :QUALITY_OF_SERVICE_DELAYABLE
        else
          :QUALITY_OF_SERVICE_FAIL_FAST
        end
      end
    end
  end
end
