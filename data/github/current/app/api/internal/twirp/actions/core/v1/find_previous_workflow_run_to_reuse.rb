# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class FindPreviousWorkflowRunToReuse
        include GitHub::Memoizer

        attr_reader :req

        def self.call(request)
          new(request).call
        end

        def initialize(request)
          @req = request
        end

        def call
          return Twirp::Error.invalid_argument("missing repository_id", argument: "repository_id") if req.repository_id.blank?
          return Twirp::Error.invalid_argument("missing workflow_path", argument: "workflow_path") if req.workflow_path.blank?
          return Twirp::Error.invalid_argument("missing event_type", argument: "event_type") if req.event_type.blank?
          return Twirp::Error.invalid_argument("missing commit_sha", argument: "commit_sha") if req.commit_sha.blank?
          return Twirp::Error.not_found("repository does not exist", argument: "repository_id") unless repository
          return Twirp::Error.not_found("commit with the following sha in the repository does not exist", argument: "commit_sha") unless commit
          return Twirp::Error.invalid_argument("event_type #{req.event_type} is not supported", argument: "event_type") unless Actions::WorkflowRun::SUPPORTED_REUSE_EVENT_TYPES.include?(req.event_type)

          tree_id = commit.tree_oid
          if workflow.nil?
            return {
              tree_id: tree_id
            }
          end

          # https://github.com/github/c2c-actions/blob/main/docs/adrs/5554-green-trees.md#5-the-workflow_runs-table-will-save-the-information-in-dotcom
          # For a run to be reused the following conditions need to be met:
          # - same repository (repository_id)
          # - same workflow (worklow_id)
          # - one of the few supported event types (event)
          # - same tree_id (tree_id)
          # - The most recent workflow run is succesful (conclusion and status)
          # - The run is not an existing clone (cloned_workflow_run_id)
          #
          # index_workflow_runs_on_repository_id_workflow_id_event_tree_id is optimized for the first query below. Conclusions and completed_at are delegated to the parent check suite which is why it's preloaded
          matching_workflow_runs = Actions::WorkflowRun.preload(:check_suite).where(repository_id: repository.id, workflow_id: workflow.id, event: Actions::WorkflowRun::SUPPORTED_REUSE_EVENT_TYPES, tree_id: tree_id)
          matching_completed_runs = matching_workflow_runs.filter { |run| run.completed? && !run.is_clone? }
          most_recent_completed_run = matching_completed_runs.sort_by!(&:completed_at).first

          if most_recent_completed_run.present? && most_recent_completed_run.conclusion == "success"
            {
              tree_id: tree_id,
              check_suite_to_clone: {
                check_suite_global_id: {
                  global_id: get_global_id(most_recent_completed_run.check_suite)
                },
                check_suite_database_id: most_recent_completed_run.check_suite_id
              }
            }
          else
            {
              tree_id: tree_id
            }
          end
        end

        memoize def repository
          type, id = Platform::Helpers::NodeIdentification.from_global_id(req.repository_id.global_id)
          Repository.find_by(id: id) if type == "Repository"
        end

        memoize def commit
          begin
            Repositories.domain.commits.by_oid(repository: repository, commit_oid: req.commit_sha)
          rescue GitRPC::ObjectMissing
            nil
          end
        end

        memoize def workflow
          Actions::Workflow.find_by(repository_id: repository.id, path: req.workflow_path, imposer_repository_id: 0)
        end

        def get_global_id(check_suite)
          use_next_gid = !GitHub.enterprise?
          use_next_gid ? check_suite.next_global_id : check_suite.global_relay_id
        end
      end
    end
  end
end
