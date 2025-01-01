# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    # Perform the bulk of the read operations on our dependencies in a single location. Ensure we're performing as many
    # batch operations as possible.
    class Loader
      extend T::Sig
      include Scientist
      include GitHub::Memoizer

      sig { params(repository: Repository).void }
      def initialize(repository:)
        @repository = repository
      end

      # Builds a Configuration object for the given Repository.
      sig { returns(Configuration) }
      memoize def configuration
        with_telemetry(:configuration) do
          Loaders::Configurations.build(@repository)
        end
      end

      # PullRequests needing merge commits created.
      sig { returns(T::Array[PullRequest]) }
      memoize def pull_requests
        with_telemetry(:pull_requests) do
          return [] if merge_commit_requests.empty?

          models = PullRequest
            .includes(:user, :head_repository, :base_repository, :conflict)
            .includes(repository: :parent_advisory)
            .where(
              repository: @repository,
              id: merge_commit_requests.map(&:pull_request_id).compact.uniq
            ).to_a

          # We default to reading from the primary for the issues-pull-requests
          # cluster. For `PullRequest` and `MergeCommitRequest` records it's
          # important to have the freshest data, but for `Issue` we can afford
          # a little replication lag, so we use a replica to load those records.
          ActiveRecord::Base.connected_to(role: :reading) do
            GitHub::PrefillAssociations.prefill_associations(models, [:issue])
          end

          models
        end
      end

      # Builds the collection of Request structures describing the Pull Request to be updated.
      sig { returns([T::Array[Request], T::Array[Request::Invalid]]) }
      memoize def requests
        with_telemetry(:requests) do
          requests = T.let([], T::Array[Request])
          invalid_requests = T.let([], T::Array[Request::Invalid])

          return [requests, invalid_requests] if merge_commit_requests.empty?

          Loaders::Requests.new(merge_commit_requests, pull_requests).build.each do |request|
            case request
            when Request
              requests << request
            when Request::Invalid
              invalid_requests << request
            else
              T.absurd(request)
            end
          end

          [requests, invalid_requests]
        end
      end

      # Load without ActiveRecord models the pull requests and their state for the current run.
      sig { returns(T::Array[MergeCommitRequest]) }
      memoize def merge_commit_requests
        with_telemetry(:merge_commit_requests) do
          MergeCommitRequest
            .where(repository_id: @repository.id)
            .order("created_at ASC")
            .limit(configuration.batch_size)
            .to_a
        end
      end

      private

      sig { params(name: Symbol).returns(T::Boolean) }
      def feature_enabled?(name)
        @repository.feature_enabled?(name)
      end

      sig do
        type_parameters(:T)
          .params(name: Symbol, block: T.proc.returns(T.type_parameter(:T)))
          .returns(T.type_parameter(:T))
      end
      def with_telemetry(name, &block)
        GitHub.tracer.in_span("merge_commits.loader.#{name}", kind: :internal) do
          GitHub.dogstats.distribution_time("merge_commits.loader.duration", tags: ["action:#{name}"], &block)
        end
      end
    end
  end
end
