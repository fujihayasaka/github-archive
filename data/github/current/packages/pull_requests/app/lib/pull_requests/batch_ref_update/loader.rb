# typed: strict
# frozen_string_literal: true

module PullRequests
  module BatchRefUpdate
    class Loader
      include GitHub::Memoizer

      sig do
        params(
          repository: Repository,
          ref_update_requests: T::Array[DatabaseRecord]
        ).void
      end
      def initialize(repository:, ref_update_requests:)
        @repository = repository
        @ref_update_requests = ref_update_requests
      end

      sig { returns(T::Array[Request]) }
      def requests
        requests = T.let([], T::Array[Request])

        ref_update_requests.each do |request|
          commits.request(@repository, request.before_sha)
          commits.request(@repository, request.after_sha)
          refs.request(@repository, request.ref_name)
        end

        ref_update_requests.each do |request|
          before_commit = commits.read(@repository, request.before_sha)
          after_commit = commits.read(@repository, request.after_sha)
          ref_sha = refs.read(@repository, request.ref_name)

          case before_sha = request.before_sha
          when GitHub::NULL_OID
            # This is a create request, so we don't need to validate the before_sha.
          when String
            if before_commit.nil?
              # Request is ineligible because before_sha does not exist.
              requests << Request::Ineligible.new(
                pull_request_id: request.pull_request_id,
                ref_name: request.ref_name,
                before_sha:,
                reason: Enums::Failures::BaseCommitNotFound
              )
              next
            elsif ref_sha != before_sha
              # Request is ineligible because before_sha is not the same as the ref's current sha.
              requests << Request::Ineligible.new(
                pull_request_id: request.pull_request_id,
                ref_name: request.ref_name,
                before_sha:,
                reason: Enums::Failures::GitError
              )
              next
            end
          when nil
          else T.absurd(before_sha)
          end

          case after_sha = request.after_sha
          when GitHub::NULL_OID
            # This is a delete request, so we don't need to validate the after_sha.
          else
            if after_commit.nil?
              # Request is ineligible because after_sha does not exist.
              requests << Request::Ineligible.new(
                pull_request_id: request.pull_request_id,
                ref_name: request.ref_name,
                before_sha:,
                after_sha:,
                reason: Enums::Failures::HeadCommitNotFound
              )
              next
            end
          end
          requests << Request::Eligible.new(
            pull_request_id: request.pull_request_id,
            ref_name: request.ref_name,
            before_sha:,
            after_sha:,
          )
        end

        with_telemetry(:pull_requests) do
          PullRequest.where(id: ref_update_requests.map(&:pull_request_id).compact.uniq)
        end

        requests
      end

      private

      sig do
        type_parameters(:T)
          .params(name: Symbol, block: T.proc.returns(T.type_parameter(:T)))
          .returns(T.type_parameter(:T))
      end
      def with_telemetry(name, &block)
        GitHub.tracer.in_span("pull_requests.batch_ref_update.loader.#{name}", kind: :internal) do
          GitHub.dogstats.distribution_time("pull_requests.batch_ref_update.loader.duration", tags: ["action:#{name}"], &block)
        end
      end

      sig { returns(GitSystems::BatchReadCommits) }
      memoize def commits
        with_telemetry(:commits) do
          GitSystems::BatchReadCommits.new
        end
      end

      sig { returns(GitSystems::BatchReadRefs) }
      memoize def refs
        with_telemetry(:refs) do
          GitSystems::BatchReadRefs.new
        end
      end

      sig { returns(T::Array[DatabaseRecord]) }
      def ref_update_requests
        # TODO: Replace me with a real database query once the migration has finished.
        @ref_update_requests
      end
    end
  end
end
