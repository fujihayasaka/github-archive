# typed: true
# frozen_string_literal: true

module Actions
  module WorkflowRuns
    class NavigationComponent < ApplicationComponent
      include ChecksHelper
      include ChecksRollupHelper
      include GitHub::Memoizer
      include KeyboardShortcutsHelper

      attr_reader :selected_check_run, :current_repository, :selected_tab

      TAB_SELECTED_CLASSES = "row-selected color-fg-default"
      TAB_UNSELECTED_CLASSES = "color-fg-muted"

      def initialize(
        check_suite:,
        selected_check_run:,
        current_repository:,
        selected_tab: nil,
        execution: nil,
        retry_blankstate: false,
        pull_request_number: nil,
        can_view_workflow_file: false
      )
        @check_suite, @selected_check_run, @current_repository, @selected_tab, @execution, @retry_blankstate, @pull_request_number, @can_view_workflow_file =
          check_suite, selected_check_run, current_repository, selected_tab, execution, retry_blankstate, pull_request_number, can_view_workflow_file
      end

      memoize def check_suite
        @check_suite || selected_check_run&.check_suite
      end

      def id_for_check_run(check_run)
        "job_#{check_run.id}".to_sym
      end

      def selected_item_id
        return id_for_check_run(selected_check_run) if selected_check_run
        selected_tab || :summary
      end

      def summary_path
        if viewing_current?
          workflow_run_path(workflow_run_id: check_suite.workflow_run.id, repository: current_repository, user_id: current_repository.owner.display_login, pr: @pull_request_number)
        else
          workflow_run_attempt_path(workflow_run_id: check_suite.workflow_run.id, repository: current_repository, user_id: current_repository.owner.display_login, attempt: @execution.attempt, pr: @pull_request_number)
        end
      end

      def pull
        if @pull_request_number && current_repository
          PullRequest.with_number_and_repo(@pull_request_number, current_repository)
        end
      end

      def usage_path
        workflow_run_usage_path(workflow_run_id: workflow_run.id, repository: current_repository, user_id: current_repository.owner.display_login, pr: @pull_request_number)
      end

      def workflow_file_path
        workflow_run_file_path(workflow_run_id: workflow_run.id, repository: current_repository, user_id: current_repository.owner.display_login, pr: @pull_request_number)
      end

      def live_update_path
        workflow_run_navigation_partial_path(
          workflow_run_id: check_suite.workflow_run.id,
          repository: current_repository,
          selected_check_run_id: selected_check_run&.id,
          selected_tab: selected_tab,
          user_id: current_repository.owner.display_login,
          pr: @pull_request_number
        )
      end

      def show_rerun_button?(check_run)
        check_suite.rerunnable? && viewing_current? && writable? && check_run.actions_rerequestable? && !check_suite.expired_logs?
      end

      memoize def writable?
        current_repository.writable_by?(current_user)
      end

      memoize def check_runs
        @_check_runs =
          if @retry_blankstate
            @_check_runs = CheckRun.none
          else
            workflow_run.latest_check_runs(execution: @execution)
          end

        @_check_runs = @_check_runs.includes(:workflow_job_run)
        @_check_runs = @_check_runs.sort_by(&:sort_order) if @_check_runs.present?
        @_check_runs
      end

      memoize def workflow_run
        check_suite.workflow_run
      end

      # True when rendering the latest execution or the overall checksuite status
      def viewing_current?
        @execution.nil? || @execution.is_latest_execution? || @retry_blankstate
      end

      # Always expand nested sub-items unless everything has succesfully passed
      def expand_list_with_sub_items?(status, conclusion)
        !(status == "completed" && conclusion == "success")
      end

      # For reusable workflows, we have nested runs, the data takes the following form and is dynamically generated
      #
      # sidebar_map = {
      #   build: {
      #     non_nested: [
      #        check_run,
      #        check_run,
      #     ],
      #     nested: {
      #       status: 'completed',
      #       conclusion: 'failure',
      #       data: [
      #         { name: "linux", check_run: check_run },
      #         { name: "windows", check_run: check_run },
      #         { name: "mac", check_run: check_run },
      #       ]
      #     }
      #   }
      #   test: {
      #     non_nested: [check_run]
      #   },
      #   validate: {
      #     non_nested: [check_run]
      #   },
      #   deploy: {
      #     nested: {
      #       status: 'completed',
      #       conclusion: 'failure',
      #       data: [
      #         { name: "staging", check_run: check_run },
      #         { name: "production", check_run: check_run },
      #       ]
      #     }
      # }
      #
      # In the UI this would then have to be disaplyed like this:
      #
      #   ✅  build     <= can have the same name as a nested run and non-nested run
      #   ✅  build     <= this is possible if the name field is explicitly specified, see https://github.com/github/c2c-actions-experience/issues/6520
      #   ❌  build
      #      ✅ linux
      #      ✅ windows
      #      ❌  mac
      #   ✅ test
      #   ✅ validate
      #   ❌  deploy
      #      ✅ staging
      #      ❌  production
      memoize def processed_sidebar_map
        sidebar_map = {}

        check_runs.each do |check_run|
          if check_run.workflow_job_run.present? && check_run.workflow_job_run.reusable_job?
            # special nested reusable job
            parent_job_name, child_job_name = check_run.reusable_workflow_display_names
            data = {
              display_name: child_job_name,
              check_run: check_run
            }

            if sidebar_map.has_key?(parent_job_name)
              existing_parent_entry = sidebar_map[parent_job_name]

              if existing_parent_entry.has_key?(:nested)
                existing_nested_entry = existing_parent_entry[:nested]
                existing_nested_entry[:data].append(data)
              else
                existing_parent_entry[:nested] = {
                  data: [data]
                }
              end
            else
              sidebar_map[parent_job_name] = {
                nested: {
                  data: [data]
                }
              }
            end
          else
            # just a normal actions job or a check run created using GITHUB_TOKEN
            if sidebar_map.has_key?(check_run.visible_name)
              if sidebar_map[check_run.visible_name].has_key?(:non_nested)
                sidebar_map[check_run.visible_name][:non_nested].prepend(check_run)
              else
                sidebar_map[check_run.visible_name][:non_nested] = [check_run]
              end
            else
              sidebar_map[check_run.visible_name] = {
                non_nested: [check_run]
              }
            end
          end
        end

        # calculate rollup status and conclusion for each nested job
        sidebar_map.each do |_parent_name, details|
          if details.has_key?(:nested)
            check_runs = details[:nested][:data].pluck(:check_run)
            details[:nested][:status] = calculate_rollup_status(check_runs)
            details[:nested][:conclusion] = calculate_rollup_conclusion(check_runs)
          end
        end

        sidebar_map
      end

      def can_view_workflow_file?
        @can_view_workflow_file
      end
    end
  end
end
