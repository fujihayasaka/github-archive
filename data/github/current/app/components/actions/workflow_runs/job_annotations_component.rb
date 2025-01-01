# typed: true
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

module Actions
  module WorkflowRuns
    class JobAnnotationsComponent < ApplicationComponent

      attr_reader :check_run, :workflow_run, :workflow_file_path, :commit, :current_repository, :all_annotations, :steps, :ux_refresh

      def initialize(check_run:, workflow_run:, workflow_file_path:, commit:, current_repository:, annotations:, steps:, ux_refresh:)
        @check_run = check_run
        @workflow_run = workflow_run
        @workflow_file_path = workflow_file_path
        @commit = commit
        @current_repository = current_repository
        @all_annotations = annotations
        @steps = steps
        @ux_refresh = ux_refresh
      end

      def render?
        all_annotations.any?
      end

      memoize def annotations
        all_annotations.sort_by { |a| [a.warning_level_to_i, a.id] }
      end

      def message(annotation)
        GitHub::Goomba::ActionsAnnotationPipeline.to_html(annotation.message)
      end

      def num_annotations
        num_errors + num_warnings + num_notices
      end

      memoize def num_errors
        annotations.count { |a| a.error? }
      end

      memoize def num_warnings
        annotations.count { |a| a.warning? }
      end

      memoize def num_notices
        annotations.count { |a| a.notice? }
      end

      memoize def step_numbers_to_names
        steps.pluck(:number, :name).to_h
      end

      def subtitle
        errors = "#{num_errors} #{"error".pluralize(num_errors)}" if num_errors > 0
        warnings = "#{num_warnings} #{"warning".pluralize(num_warnings)}" if num_warnings > 0
        notices = "#{num_notices} #{"notice".pluralize(num_notices)}" if num_notices > 0
        [errors, warnings, notices].compact.to_sentence
      end

      def octicon_for(annotation)
        if annotation.error?
          octicon "x-circle-fill", class: "mr-2 color-fg-danger"
        elsif annotation.notice?
          octicon "info", class: "mr-2 color-fg-muted"
        else
          octicon "alert", class: "mr-2 color-fg-attention", style: "margin-top: 1px"
        end
      end

      def step_name_for_annotation(step_number)
        step_numbers_to_names[step_number]
      end

      def link_to_line(annotation)
        # Annotation links out to the workflow file. Mostly for startup_failure scenarios but there are other cases
        if annotation.path == workflow_file_path
          return workflow_run_file_path(workflow_run_id: workflow_run.id, user_id: current_repository.owner.display_login, repository: current_repository)
        end

        # Most annotations created by actions have .github as the path and map to a step and a line number
        if annotation.system_path?
          if annotation.step_number.present?
            return "#annotation:#{annotation.step_number}:#{annotation.start_line}"
          else
            return check_run.permalink(check_suite_focus: true)
          end
        end

        # From the PR diff view, annotations have the following behavior:
        # - changed files with annotations are displayed (at all positions, even if the lines are not explicitly in the diff)
        # - unchanged files with check annotations are displayed at the bottom (currently in Beta)
        if workflow_run.trigger.is_a? PullRequest
          pr_path = pull_request_path(workflow_run.trigger)
          return "#{pr_path}/files#annotation_#{annotation.id}"
        end

        # In all other scenarios link out to the commit diff, from that view annotations have the following behavior:
        # - changed files have annotations displayed only if the line numbers match up with the commit diff, if outside then nothing is displayed
        # - unchanged files with check annotations are not displayed anywhere
        "#{commit_path(commit)}#annotation_#{annotation.id}"
      end
    end
  end
end
