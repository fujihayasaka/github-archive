# typed: true
# frozen_string_literal: true

module ActionsPrompt
  class AbstractActionsTask
    include UrlHelper

    WORKFLOWS_LOCATION = {
      python: {
        filename: ".github/workflows/python-app.yml",
        workflow_template: "python-app"
      },
      go: {
        filename: ".github/workflows/go.yml",
        workflow_template: "go"
      },
      html: {
        filename: ".github/workflows/jekyll.yml",
        workflow_template: "jekyll"
      }
    }.freeze

    def completed?
      return @completed if defined?(@completed)

      @completed = has_actions_workflow?
    end

    def task_link
      workflow_data = WORKFLOWS_LOCATION[primary_language]
      blob_new_path("", task_ref, repository) + "?" +
      {
        filename: workflow_data[:filename],
        workflow_template: workflow_data[:workflow_template],
      }.to_query
    end

    def repo_candidate?
      raise NotImplementedError
    end

    private

    def task_ref
      raise NotImplementedError
    end

    def repository
      raise NotImplementedError
    end

    def has_actions_workflow?
      return @has_actions_workflow if defined?(@has_actions_workflow)

      @has_actions_workflow = Actions::WorkflowRun.where(repository_id: repository.id).exists?
    end

    def primary_language
      return @primary_language if defined?(@primary_language)

      @primary_language = repository.primary_language&.name&.downcase&.to_sym
    end

    def supported_primary_language?
      primary_language.in?(WORKFLOWS_LOCATION) && available_workflow_template?
    end

    def available_workflow_template?
      return true unless primary_language == :html

      # If the primary language is HTML, we need to check if there is a possible Jekyll framework
      # available in the repository
      repo_languages = repository.top_languages_summarized
      return false unless repo_languages.present?

      repo_languages.any? { |language| language[0].downcase == "ruby" }
    end
  end
end
