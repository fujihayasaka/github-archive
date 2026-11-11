# typed: true
# frozen_string_literal: true

module PullRequests::ChecksDependency
  extend T::Helpers
  include GitHub::Memoizer
  include ControllerMethods::CheckAnnotations

  requires_ancestor { AbstractRepositoryController }

  sig { returns(T.nilable(CheckRun)) }
  memoize def selected_check_run
    check_run_id = params[:check_run_id] && Integer(params[:check_run_id], exception: false)

    if check_run_id
      Checks.domain.check_runs.for_id(check_run_id, repository_id: current_repository.id)
    end
  end

  sig { params(pull: PullRequest).returns(T::Hash[Symbol, T.untyped]) }
  def checks_partial_data(pull)
    sha = selected_check_run&.head_sha || params[:sha] || pull.head_sha
    commit = pull.changed_commits.find { |commit| commit.oid == sha }
    check_suites = pull.matching_check_suites(head_sha: sha)

    resolved_selected_check_run = selected_check_run
    resolved_selected_check_run ||= if check_suite = T.let(check_suites.first, T.nilable(CheckSuite))
      Checks.domain.check_runs.first_for_check_suite(check_suite)
    end

    {
      pull: pull,
      commit: commit,
      selected_check_run: resolved_selected_check_run,
      check_suites: check_suites,
      annotation_details: annotation_details_for_check_run(resolved_selected_check_run),
      commit_check_runs: commit_check_runs(commit),
      blankslate: show_blankslate?(check_suites, resolved_selected_check_run, current_repository),
      workflows_loading: workflows_loading?(check_suites, resolved_selected_check_run)
    }
  end

  private

  sig { params(check_suites: ActiveRecord::Relation, selected_check_run: T.nilable(CheckRun), current_repository: T.untyped).returns(T::Boolean) }
  def show_blankslate?(check_suites, selected_check_run, current_repository)
    return false if check_suites.any?
    return false if selected_check_run
    return false if current_repository.has_apps_that_write_checks?
    true
  end

  sig { params(check_suites: ActiveRecord::Relation, selected_check_run: T.nilable(CheckRun)).returns(T::Boolean) }
  def workflows_loading?(check_suites, selected_check_run)
    # selected_check_run will be nil if no check runs have been created (yet)
    return false if selected_check_run

    check_suites.any? { |check_suite| check_suite.actions_app? && !check_suite.completed? }
  end

  sig { params(commit: T.untyped).returns(T.any(ActiveRecord::Relation, T::Array[T.untyped])) }
  def commit_check_runs(commit)
    return [] unless commit

    CheckRun.for_sha_and_repository_id_with_limit(current_repository.id, commit.oid, CheckRun.default_max_check_suites_per_sha_limit)
  end

  def annotation_details_for_check_run(check_run)
    return nil unless check_run

    load_annotation_details(check_run: check_run)
  end
end
