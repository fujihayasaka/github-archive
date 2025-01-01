# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    # Generate PORO's describing the request. This validates and generates objects based off
    module Loaders
      class Requests
        extend T::Sig
        include GitHub::Memoizer

        sig { params(merge_commit_requests: T::Array[MergeCommitRequest], pull_requests: T::Array[PullRequest]).void }
        def initialize(merge_commit_requests, pull_requests)
          @merge_commit_requests = merge_commit_requests
          @pull_requests = pull_requests
        end

        sig { returns(T::Array[T.any(Request, Request::Invalid)]) }
        def build
          requests = T.let([], T::Array[T.any(Request, Request::Invalid)])

          # Collection of PRs that have valid database state and are generally eligible.
          eligible_pulls = T.let([], T::Array[[PullRequest, Repository, Repository, Time]])

          # First pass to filter out Pulls we know can't ever be processed.
          @merge_commit_requests.each do |merge_commit_request|

            next unless record_created_at = T.let(merge_commit_request.created_at&.time, T.nilable(Time))

            pull_request_id = merge_commit_request.pull_request_id.to_i

            unless pull = @pull_requests.find { _1.id == pull_request_id }
              next requests << Request::Invalid.new(reason: Request::Invalid::Reason::MissingPullRequest, pull_request_id:, record_created_at:)
            end

            # Ignore duplicate requests for PRs.
            if eligible_pulls.any? { |(pull_request, _)| pull_request == pull }
              next requests << invalid(Request::Invalid::Reason::DuplicateRequest, pull:, record_created_at:)
            end

            pull_request_number = pull.number

            if pull.merged_at? || pull.closed?
              next requests << invalid(Request::Invalid::Reason::ClosedOrMerged, pull:, record_created_at:)
            end

            unless repository = pull.repository
              next requests << invalid(Request::Invalid::Reason::MissingRepository, pull:, record_created_at:)
            end

            base_repository = if repository.advisory_workspace?
              repository.parent_advisory_repository
            else
              pull.base_repository
            end

            unless base_repository
              next requests << invalid(Request::Invalid::Reason::MissingBaseRepository, pull:, record_created_at:)
            end

            head_repository = if repository.advisory_workspace?
              repository
            else
              pull.head_repository
            end

            unless head_repository
              next requests << invalid(Request::Invalid::Reason::MissingHeadRepository, pull:, record_created_at:)
            end

            eligible_pulls << [pull, base_repository, head_repository, record_created_at]
          end

          # Queue up batch requests.
          eligible_pulls.each do |(pull, base_repository, head_repository, _)|
            commits.request(base_repository, pull.merge_commit_sha)
            refs.request(base_repository, pull.qualified_base_ref_name)
            refs.request(head_repository, pull.qualified_head_ref_name)
          end

          with_telemetry(:refs) { refs.execute }
          with_telemetry(:commits) { commits.execute }

          # Execute the batches and determine eligibility of remaining pull requests.
          eligible_pulls.each do |(pull, base_repository, head_repository, record_created_at)|
            base_ref_name = pull.qualified_base_ref_name
            head_ref_name = pull.qualified_head_ref_name
            pull_request_id = pull.id.to_i
            pull_request_number = pull.number

            unless base_ref_sha = refs.read(base_repository, base_ref_name)
              next requests << invalid(Request::Invalid::Reason::MissingBaseRefSha, pull:, record_created_at:)
            end

            unless head_ref_sha = refs.read(head_repository, head_ref_name)
              next requests << invalid(Request::Invalid::Reason::MissingHeadRefSha, pull:, record_created_at:)
            end

            # PullRequest#synchronize! will automatically clear the mergeable bit, so we need to utilize existing conflict
            # data to determine previous conflict state. Without this, we will send excess mergeability events.
            previous_mergeability = if mergeable = pull.mergeable
              Request::Mergeability::Mergeable
            elsif mergeable == false || pull.conflict.present?
              Request::Mergeability::Conflict
            else
              Request::Mergeability::Indeterminate
            end

            commit = commits.read(base_repository, pull.merge_commit_sha)

            # Determine if our merge commit is up to date, if there is one.
            if commit&.parent_oids == [base_ref_sha, head_ref_sha]
              case previous_mergeability
              when Request::Mergeability::Mergeable
                next requests << invalid(Request::Invalid::Reason::MergeableAndUpToDate, pull:, record_created_at:)
              when Request::Mergeability::Indeterminate
                next requests << invalid(Request::Invalid::Reason::IndeterminateAndUpToDate, pull:, record_created_at:)
              end
            end

            # This request is valid for execution.
            requests << Request.new(
              previous_mergeability:,
              record_created_at:,
              base_ref_name:,
              base_ref_sha:,
              head_ref_name:,
              head_ref_sha:,
              pull_request_id:,
              pull_request_number:,
              pull_request_base_sha: pull.base_sha || GitHub::NULL_OID,
              pull_request_head_sha: pull.head_sha || GitHub::NULL_OID,
              pull_request_head_repository_id: head_repository.id,
              pull_request_base_repository_id: base_repository.id,
              merge_ref_name: pull.merge_ref,
              rebase_ref_name: pull.rebase_ref,
            )
          end

          requests
        end

        private

        sig { params(reason: Request::Invalid::Reason, pull: PullRequest, record_created_at: Time).returns(Request::Invalid) }
        def invalid(reason, pull:, record_created_at:)
          Request::Invalid.new(reason:,
            pull_request_id: pull.id.to_i,
            pull_request_number: pull.number,
            record_created_at:,
          )
        end

        sig { returns(Loaders::Refs) }
        memoize def refs
          Loaders::Refs.new
        end

        sig { returns(Loaders::Commits) }
        memoize def commits
          Loaders::Commits.new
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
end
