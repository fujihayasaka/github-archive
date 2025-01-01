# typed: false
# frozen_string_literal: true

module StacksHelper
  module Status
    IN_PROGRESS = "in_progress"
    NOT_STARTED = "not_started"
    SUCCESS = "success"
    FAILED = "failed"
  end

  module StepName
    REPO_CLONING = "repo-cloning"
    CONFIG = "config"
    WORKFLOW_RUN = "workflow-run"
    STACK_CLEANUP = "stack-cleanup"
  end

  module Constants
    SUCCESS = "success"
    COMPLETED = "completed"
  end

  # Public: Whether to show the "Use this Stack" button on a Stack-template repository,
  # so the viewer can use the Stack-template to make a new repository.
  #
  # repo - the Repository being viewed
  #
  # Returns a Boolean.
  def show_stack_template_button?(repo)
    false
  end

  # Public: Whether to show the "Stack label and icon" along with the repository
  #
  # repo - the Repository being viewed
  #
  # Returns a Boolean.
  def show_stack_template_labels_icons?(repo)
    false
  end

  # Public: Given a owner and repository, fetch the repo object model from db
  #
  # owner_login - String of owner_login
  # repo_name - String of a Repository name
  # current_user - User object for current user
  #
  # Returns a Repository object.
  def self.search_repository_by_user_name(owner_login, repo_name, current_user)
    return nil unless repo = Repository.active.filter_spam_and_disabled_for(current_user).
               find_by(owner_login: owner_login, name: repo_name)
    return nil unless repo.readable_by?(current_user)
    repo
  end

  # Public: Given a repository_id, fetch the repo object model from db
  #
  # repository_id - Id of a Repository
  # current_user - User object for current user
  #
  # Returns a Repository object.
  def self.search_repository_by_id(repository_id, current_user)
    return nil unless repo = Repository.active.filter_spam_and_disabled_for(current_user).
               find_by_id(repository_id)
    return nil unless repo.readable_by?(current_user)
    repo
  end

  # Public: Given a workflow_run instance,  get its status
  # workflow_run - a WorkflowRun object
  #
  # Returns a String
  def get_status(workflow_run)
    if workflow_run.completed?
      return workflow_run.success? ? Status::SUCCESS : Status::FAILED
    end
    Status::IN_PROGRESS
  end

  # Public: Given a workflow run, get annotations for the run
  #
  # workflow_run - a Workflow run object
  #
  # Returns a list of annotations
  def find_latest_annotations(workflow_run)
    return [] unless !workflow_run.nil?
    check_suite = workflow_run.check_suite
    check_suite_annotations = check_suite.annotations.where("created_at >= ?", check_suite.started_at || check_suite.created_at)
    latest_check_run_ids = Checks.domain.check_runs.latest_ids_for_check_suite(check_suite)

    check_run_annotations = CheckAnnotation
      .includes(:check_run)
      .where(repository: workflow_run.repository)
      .where("check_run_id in (?)", latest_check_run_ids)

    check_run_annotations.to_a + check_suite_annotations.to_a
  end

  # Public: Returns the integrations's very short description without a trailing period and with
  # ampersands replaced by the word "and".
  def normalized_short_description(integration)
    (integration.description || "").gsub(/&/, "and").gsub(/\.\z/, "")
  end
end
