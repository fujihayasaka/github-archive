# typed: true
# frozen_string_literal: true

module Pages
  class WorkflowCardComponent < ApplicationComponent

    TEMPLATE_REPO = "actions/starter-workflows"

    def initialize(repository:, user:, id:)
      @repository = repository
      @user = user
      @id = id
    end

    def repository
      @repository
    end

    def name
      template["name"]
    end

    def author
      template["creator"]
    end

    def description
      template["description"]
    end

    def icon
      template["iconRawUrl"]
    end

    def id
      @id
    end

    private

    memoize def template
      PagesWorkflowTemplate.get_template_by_id(@id, @repository, @user) || {}
    end
  end
end
