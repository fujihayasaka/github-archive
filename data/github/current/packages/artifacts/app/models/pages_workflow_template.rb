# typed: true
# frozen_string_literal: true

class PagesWorkflowTemplate

  TEMPLATE_REPO = "actions/starter-workflows"

  DEFAULT_BRANCH = "main"

  PAGES_CONTENT = %w[pages icons]

  def self.get_yaml_by_id(id, repo, user)
    # Lookup the template to return
    template = self.get_template_by_id(id, repo, user)
    return "" unless template

    # Expand built-in variables
    yaml = Base64.decode64(template["data"])
    Actions::WorkflowTemplates.process_workflow_templating(yaml, repo)
  end

  def self.get_template_by_id(id, repo, user)
    self.templates(repo, user).find do |template|
      template["id"] == id
    end
  end

  def self.templates(repo, user)
    Actions::WorkflowTemplatesLoader.new(TEMPLATE_REPO, PAGES_CONTENT, "default", user).all
  end
end
