# typed: true
# frozen_string_literal: true

module CodeScanning
  class PullRequestAlertSummarizer
    include ActionView::Helpers::NumberHelper
    include ActionView::Helpers::TextHelper

    # Metadata
    attr_reader :pull_request_number
    attr_reader :repository
    attr_reader :tool_name
    attr_reader :latest_upload_time
    attr_reader :diff_truncated

    # New alerts and counts
    attr_reader :new_alerts
    attr_reader :new_count
    attr_reader :security_critical_count
    attr_reader :security_high_count
    attr_reader :security_medium_count
    attr_reader :security_low_count
    attr_reader :error_count
    attr_reader :warning_count
    attr_reader :note_count

    # Fixed alerts
    attr_reader :fixed_alerts
    attr_reader :fixed_count

    CATEGORIES_BYTE_LIMIT = 50000.freeze

    def initialize(attrs = {})
      attrs.each do |key, value|
        instance_variable_set("@#{key}", value)
      end
    end

    def conclusion
      if security_severity_count > 0 || severity_count > 0
        "failure"
      elsif missing_category_count > 0
        "neutral"
      else
        "success"
      end
    end

    def title
      return pluralize(missing_category_count, "configuration") + " not found" if missing_category_count > 0

      segments = []
      if new_count > 0
        segments << "#{number_with_delimiter(new_count)} new #{"alert".pluralize(new_count)}"
        if security_critical_count > 0
          segments << "including #{number_with_delimiter(security_critical_count)} critical severity security #{"vulnerability".pluralize(security_critical_count)}"
        elsif security_high_count > 0
          segments << "including #{number_with_delimiter(security_high_count)} high severity security #{"vulnerability".pluralize(security_high_count)}"
        elsif security_medium_count > 0
          segments << "including #{number_with_delimiter(security_medium_count)} medium severity security #{"vulnerability".pluralize(security_medium_count)}"
        elsif security_low_count > 0
          segments << "including #{number_with_delimiter(security_low_count)} low severity security #{"vulnerability".pluralize(security_low_count)}"
        elsif error_count > 0
          segments << "including #{number_with_delimiter(error_count)} #{"error".pluralize(error_count)}"
        end
        segments = [segments.join(" ")]
      end

      if segments.present?
        segments.join(", ")
      else
        "No new alerts in code changed by this pull request"
      end
    end

    def summary
      sections = []

      sections += missing_category_warning if missing_category_count > 0
      sections += alert_summary

      sections.compact.join("\n\n").strip
    end

    def onboarding_experience_comment?
      return false if repository.fork?

      @new_categories.any?
    end

    def onboarding_experience_comment
      @onboarding_experience_comment ||= <<-MARKDOWN.strip_heredoc.gsub("\n", " ")
        This pull request sets up GitHub code scanning for this repository.
        Once the scans have completed and the checks have passed, the analysis results for this pull request branch
        will appear on [this overview](#{code_scanning_pr_index_path}).
        Once you merge this pull request, the 'Security' tab will show more code scanning analysis results
        (for example, for the default branch). Depending on your configuration and choice of analysis tool,
        future pull requests will be annotated with code scanning analysis results.
        For more information about GitHub code scanning, check out
        [the documentation](#{DocsUrlConfig.url_for("code-security/about-code-scanning")}).
      MARKDOWN
    end

    def missing_category_warning
      groups = missing_configuration_groups
      missing_configuration_groups_count = groups.sum { |x| x.categories.length }

      warning = []
      if new_count > 0
        warning << "**Warning**: Code scanning may not have found all "
      else
        warning << "**Warning**: Code scanning cannot determine "
      end
      warning << "the alerts introduced by this pull request, because "
      warning << pluralize(missing_category_count, "configuration")
      warning << " present on `#{@base_ref_name}`"
      warning << " #{"was".pluralize(missing_category_count)} not found"
      warning << ". The first #{pluralize(missing_configuration_groups_count, "configuration")} #{"was".pluralize(missing_configuration_groups_count)}" if missing_category_count > missing_configuration_groups_count
      warning << ":\n"
      groups.each do |configuration_group|
        warning << "\n### #{configuration_group.name}\n\n"
        configuration_group.categories.each do |category|
          warning << "* "

          # We have to check both refs in order to cover both on_push and pull request workflows
          in_progress = repository.code_scanning_action_in_progress(@merge_ref_name, @merge_commit_oid, category) || repository.code_scanning_action_in_progress(@head_ref_name, @head_commit_oid, category)
          if in_progress
            warning << ":hourglass:"
          else
            warning << ":question:"
          end

          warning << "&nbsp;&nbsp;"
          if category.present?
            warning << "`#{category}`"
          else
            warning << "&lt;default&gt;"
          end
          warning << "\n"
        end
      end

      [warning.map { |w| w.dup.force_encoding(Encoding::UTF_8).scrub! }.join("")]
    end

    def alert_summary
      alert_diff_summary + all_alerts_summary_link
    end

    def alert_diff_summary
      [
        new_alerts_summary,
        fixed_alerts_summary
      ]
    end

    def diff_truncated?
      diff_truncated
    end

    def new_alerts_summary
      return unless new_alerts.present?

      lines = []
      lines << "### New alerts in code changed by this pull request"
      lines << ""
      if security_critical_count > 0 || security_high_count > 0 || security_medium_count > 0 || security_low_count > 0
        lines << "Security Alerts:"
        lines << " * #{number_with_delimiter(security_critical_count)} critical" if security_critical_count > 0
        lines << " * #{number_with_delimiter(security_high_count)} high" if security_high_count > 0
        lines << " * #{number_with_delimiter(security_medium_count)} medium" if security_medium_count > 0
        lines << " * #{number_with_delimiter(security_low_count)} low" if security_low_count > 0
        lines << ""

        if error_count > 0 || warning_count > 0 || note_count > 0
          lines << "Other Alerts:"
        end
      end

      lines << " * #{number_with_delimiter(error_count)} #{"error".pluralize(error_count)}" if error_count > 0
      lines << " * #{number_with_delimiter(warning_count)} #{"warning".pluralize(warning_count)}" if warning_count > 0
      lines << " * #{number_with_delimiter(note_count)} #{"note".pluralize(note_count)}" if note_count > 0

      if diff_truncated?
        lines << ""
        lines << "_Alerts not introduced by this pull request might have been detected because the code changes were too large._"
      end

      lines << ""
      lines << "See annotations below for details."

      lines.join("\n")
    end

    def fixed_alerts_summary
      return unless fixed_alerts.present?

      lines = []
      lines << "### Fixed alerts in code changed by this pull request"
      lines << ""
      lines << "You may have fixed #{pluralize(fixed_count, "alert")} in this pull request."
      lines << ""
      fixed_alerts.each do |alert|
        description = alert.rule_short_description&.truncate(CheckRun::CodeScanningDependency::RULE_SHORT_DESCRIPTION_LENGTH_LIMIT)
        lines << "  * [#{description}](#{result_path(alert)}) (#{alert.location.file_path}:#{alert.location.start_line})"
      end

      lines.join("\n")
    end

    def result_path(alert)
      UrlHelpers.repository_code_scanning_result_path(@repository.owner, @repository, number: alert.number)
    end

    def all_alerts_summary_link
      return [] unless pull_request_number.present?

      ["[View all branch alerts](#{code_scanning_pr_tool_index_path})."]
    end

    def code_scanning_pr_index_path
      query = Search::Query.stringify([[:pr, pull_request_number], [:is, :open]])
      UrlHelpers.repository_code_scanning_results_path(repository.owner, repository, query: query)
    end

    def code_scanning_pr_tool_index_path
      query = Search::Query.stringify([[:pr, pull_request_number], [:tool, tool_name], [:is, :open]])
      UrlHelpers.repository_code_scanning_results_path(repository.owner, repository, query: query)
    end

    def security_severity_count
      case CodeScanningRepositoryConfig.new(repository).code_scanning_security_severity_choice
      when Configurable::CodeScanningSeverities::SECURITY_SEVERITY_NONE
        0
      when Configurable::CodeScanningSeverities::SECURITY_SEVERITY_ALL
        security_critical_count + security_high_count + security_medium_count + security_low_count
      when Configurable::CodeScanningSeverities::SECURITY_SEVERITY_MEDIUM_OR_HIGHER
        security_critical_count + security_high_count + security_medium_count
      when Configurable::CodeScanningSeverities::SECURITY_SEVERITY_HIGH_OR_HIGHER
        security_critical_count + security_high_count
      else
        security_critical_count
      end
    end

    def severity_count
      case CodeScanningRepositoryConfig.new(repository).code_scanning_severity_choice
      when Configurable::CodeScanningSeverities::SEVERITY_CHOICE_NONE
        0
      when Configurable::CodeScanningSeverities::SEVERITY_CHOICE_ALL
        error_count + warning_count + note_count
      when Configurable::CodeScanningSeverities::SEVERITY_CHOICE_ERRORS_AND_WARNINGS
        error_count + warning_count
      else
        error_count
      end
    end

    def missing_category_count
      @missing_categories.count
    end

    def missing_configuration_groups
      # Mimicks the grouping in CodeScanning::ToolConfigurationGroup.
      total_size = 0
      grouped_categories = @missing_categories.each_with_object({}) do |(category, summary), out|
        key = [summary.delivery_origin, summary.workflow_path]
        out[key] ||= []
        out[key] << category
        total_size += category.bytesize
        break out if total_size > CATEGORIES_BYTE_LIMIT
      end

      configuration_groups = grouped_categories.map do |(delivery_origin, workflow_path), categories|
        MissingConfigurationGroup.new(repository:, delivery_origin:, workflow_path:, categories: categories.sort, tool_name:)
      end
    end

    class MissingConfigurationGroup
      attr_reader :repository, :categories, :delivery_origin, :workflow_path, :tool_name

      def initialize(repository:, categories:, delivery_origin:, workflow_path:, tool_name:)
        @repository = repository
        @categories = categories
        @delivery_origin = delivery_origin
        @workflow_path = workflow_path
        @tool_name = tool_name
      end

      def name
        String.new(setup_type).tap do |out|
          if compact_workflow_path.present?
            out << " (`#{compact_workflow_path}`)"
          end
        end
      end

      private

      # TODO: Duplicates bits from CodeScanning::ToolConfigurationGroup. Refactor(?)
      def setup_type
        case delivery_origin
        when :DELIVERY_ORIGIN_YML then "Actions workflow"
        when :DELIVERY_ORIGIN_API then "API upload"
        when :DELIVERY_ORIGIN_DYNAMIC then "Dynamic workflow"
        when :DELIVERY_ORIGIN_MANAGED then "Default setup"
        when :DELIVERY_ORIGIN_UNKNOWN then tool_name
        else raise ArgumentError.new("Unknown delivery origin: #{delivery_origin}")
        end
      end

      def compact_workflow_path
        case delivery_origin
        when :DELIVERY_ORIGIN_YML
          workflow_path.delete_prefix(".github/workflows/")
        end
      end
    end
  end
end
