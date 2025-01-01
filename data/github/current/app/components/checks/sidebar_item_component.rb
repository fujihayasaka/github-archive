# typed: true
# frozen_string_literal: true

module Checks
  class SidebarItemComponent < ApplicationComponent
    include ChecksHelper
    include HydroHelper

    attr_reader :check_suite, :selected_check_run, :check_suite_selected, :check_suite_focus, :pull, :current_repository, :check_runs

    def initialize(check_suite:, selected_check_run:, check_suite_selected:, check_suite_focus:, pull:, repo_writable: nil, current_repository:)
      @check_suite = check_suite
      @selected_check_run = selected_check_run
      @check_suite_selected = check_suite_selected
      @check_suite_focus = check_suite_focus
      @pull = pull
      @repo_writable = repo_writable
      @current_repository = current_repository
      @check_runs = Checks.domain.check_runs.unsafe_latest_for_check_suite(check_suite).sort_by(&:sort_order)
    end

    memoize def annotation_count
      @check_suite.annotation_count(@check_runs.map(&:id))
    end

    def check_suite_is_user_visible?
      check_suite.user_visible?(runs: @check_runs)
    end

    def partial_path
      check_suite_show_partial_path(
        user_id: current_repository.owner_display_login,
        repository: current_repository,
        id: check_suite.id,
        selected_check_run_id: selected_check_run&.id,
        pull_id: pull&.id,
        check_suite_selected: check_suite_selected,
        check_suite_focus: check_suite_focus,
      )
    end

    def check_suite_workflow_run_path
      workflow_run_path(
        user_id: current_repository.owner_display_login,
        repository: current_repository,
        workflow_run_id: check_suite.workflow_run.id,
      )
    end

    def repo_writable?
      return @repo_writable unless @repo_writable.nil?
      @repo_writable = current_repository.writable_by?(current_user)
    end

    memoize def viewing_check_suite?
      selected_check_run&.check_suite == check_suite || check_suite_selected
    end

    memoize def check_suite_name
      check_suite.name.presence || check_suite.github_app_name
    end

    # for easier viewing, in_progress or queued check_suites should be auto-expanded even if they're not selected
    def open_check_suite?
      viewing_check_suite? || check_suite.status == "in_progress" || check_suite.status == "queued"
    end

    def check_suite_external_hydro_tracking(check_run)
      hydro_click_tracking_attributes("check_suite.external_click", {
        check_suite_id: check_suite.id,
        check_run_id: check_run.id,
        link_url: check_run.details_url,
        link_text: "Resolve"
      })
    end
  end
end
