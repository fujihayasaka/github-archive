# typed: true
# frozen_string_literal: true

module Pages
  class DeploymentWorkflowComponent < ApplicationComponent

    ENDASH_HTML = GitHub::HTMLSafeString.make("&ndash;")

    def initialize(repository:)
      @repository = repository
    end

    def repository
      @repository
    end

    memoize def page
      @repository.page
    end

    memoize def deployment
      Deployment.where(repository_id: repository.id, environment: page.environment, latest_status_state: "success").last
    end

    def display?
      # workflow_run is present when using a custom workflow, or when building a legacy jekyll workflow on actions
      page&.primary_deployment && workflow_run.present?
    end

    def learn_more_url
      "#{GitHub.help_url}/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site#publishing-with-a-custom-github-actions-workflow"
    end

    def custom_workflow?
      workflow_run && workflow_run.actor_id != GitHub.pages_github_app&.bot_id
    end

    memoize def check_suite
      deployment&.check_run&.check_suite
    end

    memoize def workflow_run
      @workflow_run = page.workflow_run
      return @workflow_run unless @workflow_run.nil?

      # use the legacy way to query workflow run
      check_suite&.workflow_run
    end

    def started_at
      return nil unless workflow_run.present?
      return workflow_run.started_at if workflow_run.started_at.present?
      workflow_run.created_at
    end

    def id
      workflow_run&.id
    end

    def file_name
      workflow_run&.name
    end
  end
end
