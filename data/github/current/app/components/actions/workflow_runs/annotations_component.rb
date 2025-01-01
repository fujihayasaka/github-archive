# typed: true
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

module Actions
  module WorkflowRuns
    class AnnotationsComponent < ApplicationComponent

      attr_reader :workflow_run, :current_repository, :commit, :all_annotations

      def initialize(workflow_run:, current_repository:, commit:, annotations:, should_update: true)
        @workflow_run = workflow_run
        @current_repository = current_repository
        @commit = commit
        @all_annotations = annotations
        @should_update = should_update
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

      def subtitle
        errors = "#{num_errors} #{"error".pluralize(num_errors)}" if num_errors > 0
        warnings = "#{num_warnings} #{"warning".pluralize(num_warnings)}" if num_warnings > 0
        notices = "#{num_notices} #{"notice".pluralize(num_notices)}" if num_notices > 0
        [errors, warnings, notices].compact.to_sentence
      end

      def name_for(annotation)
        return annotation.title unless annotation.default_title? || annotation.title == ""
        return annotation.check_run&.display_name if annotation.check_run
        return nil if annotation.path == annotation.check_suite&.workflow_file_path

        annotation.check_suite&.name
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

      def octicon_aria_label_value(annotation)
        if annotation.error?
          "Error annotation"
        elsif annotation.notice?
          "Notice annotation"
        else
          "Warning annotation"
        end
      end

      def link_to_line(annotation)
        # Check suite level annotations (as of now) can only be created internally by Actions and are normally (but not exclusively) used in the event of a startup_failure that links to problems in the YAML file
        if annotation.path == annotation.check_suite&.workflow_file_path
          return workflow_run_file_path(workflow_run_id: annotation.check_suite.workflow_run.id, user_id: current_repository.owner.display_login, repository: current_repository)
        end

        if annotation.check_suite.present? && annotation.system_path?
          return workflow_run_file_path(workflow_run_id: workflow_run.id, user_id: current_repository.owner.display_login, repository: current_repository)
        end

        if annotation.check_run.present? && annotation.system_path?
          if annotation.step_number.present?
            return "#{annotation.check_run.permalink(check_suite_focus: true)}#step:#{annotation.step_number}:#{annotation.start_line}"
          else
            return annotation.check_run.permalink(check_suite_focus: true)
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

      def live_update_channel
        workflow_run.check_suite.channel
      end

      def annotations_partial_path
        workflow_run_annotations_partial_path(
          workflow_run_id: workflow_run.id,
          repository: current_repository,
          user_id: current_repository.owner.display_login)
      end
    end
  end
end
