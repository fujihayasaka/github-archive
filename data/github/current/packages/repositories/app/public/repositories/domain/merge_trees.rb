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
      def dry_run(repository:, base_oid:, head_oid:, priority: :low)
        qos = determine_quality_of_service(priority:)
        process(repository:, base_oid:, head_oid:, mergeability_only: true, include_conflict_details: true, qos:)
      end

      # Given two trees, this will check what the state of merging those trees will be. The run method will
      # persist the objects in the repository after the merge, so we can use it after the call.
      sig do
        params(
          repository: IRepository,
          base_oid: String,
          head_oid: String,
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
      def run(repository:, base_oid:, head_oid:, priority: :low)
        qos = determine_quality_of_service(priority:)
        process(repository:, base_oid:, head_oid:, mergeability_only: false, include_conflict_details: true, qos:)
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
      def process(repository:, base_oid:, head_oid:, mergeability_only:, include_conflict_details:, qos:)  # rubocop:disable Metrics/MethodLength

        repository = T.cast(repository, Repository) # rubocop:todo GitHub/AvoidCast

        begin
          response = repository.spokes_api.with_transaction do
            repository.spokes_api.merge_trees(
              base_oid:,
              head_oid:,
              mergeability_only:,
              include_conflict_details:,
              qos:,
            )
          end
        rescue SpokesAPI::NotFound => exception
          return GH::Result::Error::NotFound.new(exception.message)
        rescue SpokesAPI::ResourceExhausted => exception
          return GH::Result::Error::ServiceRateLimited.new(exception.message)
        rescue SpokesAPI::TwirpServerError, SpokesAPI::TimedOut, SpokesAPI::Canceled, SpokesAPI::TwirpConnectionError => exception
          return GH::Result::Error::ServiceUnreachable.new(exception.message)
        end

        state = case response.merge_status
        when :STATUS_SUCCESS
          State::Mergeable.new(tree_oid: response.oid.id)
        when :STATUS_MERGE_CONFLICT
          State::Conflict.new(metadata: response.conflicts.to_h)
        when :STATUS_ALREADY_MERGED
          State::AlreadyMerged.new
        else
          State::Unmergeable.new
        end

        GH::Result::Ok.new(state)
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
