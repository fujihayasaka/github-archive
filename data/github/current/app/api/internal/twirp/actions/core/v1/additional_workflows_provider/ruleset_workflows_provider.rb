# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      module AdditionalWorkflowsProvider
        class RulesetWorkflowsProvider
          def initialize(repository, event_type, base_ref, before_oid, after_oid)
            @repository = repository
            @owner = repository.owner
            @event_type = event_type.downcase
            @base_ref = base_ref
            @before_oid = before_oid
            @after_oid = after_oid
          end

          def retrieve_ruleset_workflows
            ref_update = Git::Ref::Update.new(repository: @repository, refname: @base_ref, before_oid: @before_oid, after_oid: @after_oid)
            results = RulesEngine::WorkflowsHelper.workflows_for_ref_update(ref_update)

            results.map { |ruleset_workflow| ruleset_workflow_response_payload(ruleset_workflow) }
          end

          private

          def ruleset_workflow_response_payload(ruleset_workflow)
            source_repository = ruleset_workflow[:repository]
            {
              repository_id: global_id_response(source_repository.next_global_id),
              owner_id: global_id_response(@owner.next_global_id),
              repository_nwo: source_repository.nwo,
              path: ruleset_workflow[:path],
              ref: ruleset_workflow[:ref],
              repo_database_id: source_repository.id,
              visibility: get_repository_visibility(source_repository),
              workflow_file_sha: ruleset_workflow[:sha],
            }
          end

          def global_id_response(global_id)
            {
              global_id: global_id
            }
          end

          def get_repository_visibility(repository)
            if repository.public?
              :REPOSITORY_VISIBILITY_PUBLIC
            elsif repository.private? && repository.visibility == Repository::PRIVATE_VISIBILITY
              :REPOSITORY_VISIBILITY_PRIVATE
            elsif repository.internal?
              :REPOSITORY_VISIBILITY_INTERNAL
            else
              :REPOSITORY_VISIBILITY_INVALID
            end
          end
        end
      end
    end
  end
end
