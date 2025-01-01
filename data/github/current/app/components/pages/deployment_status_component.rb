# typed: false
# frozen_string_literal: true

module Pages
  class DeploymentStatusComponent < ApplicationComponent
    delegate(
      :avatar_for,
      to: :helpers,
    )

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
      page.primary_deployment
    end

    def file_name
      workflow_run&.name
    end

    def actor
      return nil unless workflow_run.present?
      User.find_by_id(workflow_run.actor_id)
    end

    def actor_href
      return "apps/#{actor}" if actor.is_a?(Bot)
      "#{actor&.display_login}"
    end

    def started_at
      return nil unless workflow_run.present?
      return workflow_run.started_at if workflow_run.started_at.present?
      workflow_run.created_at
    end

    memoize def workflow_run
      @workflow_run = page.workflow_run
      return @workflow_run unless @workflow_run.nil?
    end
  end
end
