# typed: false
# frozen_string_literal: true

module Elastomer::Adapters

  # The WorkflowRun adapter is used to transform a workflow run ActiveRecord object into a
  # Hash document that can be indexed in ElasticSearch.
  class WorkflowRun < ::Elastomer::Adapter

    # Public: Returns the name of the Index class responsible for storing the
    # generated documents.
    def self.index_name
      "WorkflowRuns"
    end

    def self.mysql_cluster
      ::Actions::WorkflowRun.cluster_name
    end

    # Public: Accessor for the data model instance. If the `document_id` does
    # not map to any row in the database, then `nil` is returned.
    #
    # Returns the data model instance.
    def model
      @model ||= Actions::WorkflowRun.find_by_id(document_id)
    end
    alias :workflow_run :model

    # Document routing information used to co-locate all workflow runs for a given
    # repository on a single shard in the search index.
    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def document_routing
      @document_routing ||= workflow_run&.repository_id
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    # Public: Construct a document suitable for indexing in ElasticSearch and
    # return it as a Hash.
    #
    # Returns the ElasticSearch document as a Hash.
    def to_hash
      if model.nil?
        raise Elastomer::ModelMissing, "The data model has not been set, or the document ID does not exist in the database."
      end

      return @hash if defined? @hash
      return unless workflow_run.check_suite&.repository

      if GitHub.multi_tenant_enterprise?
        # Unscoping because this job runs async where we have lost the current tenant context so the User lookup query is using a business_id of 0.
        # Calling unscope here is safe because the User lookup SQL is using an id so ambiguous data won't be returned
        creator = GitHub::CurrentTenant.unscope { workflow_run.check_suite.creator&.display_login }
        pusher = GitHub::CurrentTenant.unscope { workflow_run.check_suite.pusher&.display_login }
      else
        creator = workflow_run.check_suite.creator&.login
        pusher = workflow_run.check_suite.pusher&.login
      end

      @hash = {
        _id: document_id.to_s,
        _type: document_type,
        _routing: document_routing,
        workflow_run_id: workflow_run.id,
        check_suite_id: workflow_run.check_suite.id,
        status: workflow_run.status,
        conclusion: workflow_run.conclusion,
        head_branch: workflow_run.head_branch,
        head_sha: workflow_run.head_sha,
        head_repo_id: workflow_run.check_suite.head_repository_id,
        name: workflow_run.name,
        event: workflow_run.event,
        action: workflow_run.action,
        repo_id: workflow_run.check_suite.repository.id,
        creator: creator,
        pusher: pusher,
        workflow_name: workflow_run.workflow.name,
        workflow_id: workflow_run.workflow.id,
        title: workflow_run.title,
        lab: workflow_run.check_suite.github_app.launch_lab_github_app?,
        actor: [creator, pusher].compact,
        is: [workflow_run.status, workflow_run.conclusion].compact,
        created_at: workflow_run.created_at,
        updated_at: workflow_run.updated_at,
        archived: false, # Future use. Documents are not archived by default
        rank: 1.0,
        actor_id: workflow_run.actor&.id,
        user_hidden: workflow_run.user_hidden?,
      }
    end
  end  # WorkflowRun
end  # Elastomer::Adapters
