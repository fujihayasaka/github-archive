# typed: true
# frozen_string_literal: true

class Suggestions::SuggestedFixComponent < ApplicationComponent

  sig { returns(String) }
  attr_reader :create_pr_path

  sig { returns(Turboscan::Proto::SuggestedFix) }
  attr_reader :suggested_fix

  sig { returns(T.untyped) }
  attr_reader :generated_at

  sig { returns(T.untyped) }
  attr_reader :alert_location

  sig { returns(String) }
  attr_reader :alert_title

  sig { returns(String) }
  attr_reader :alert_description_html

  sig { returns(T.nilable(String)) }
  attr_reader :alert_code_paths_url

  sig { returns(T.nilable(Symbol)) }
  attr_reader :alert_rule_severity

  sig { returns(T.nilable(String)) }
  attr_reader :alert_help_html

  sig { returns(T.nilable(String)) }
  attr_reader :alert_tool_name

  sig { returns(Integer) }
  attr_reader :alert_number

  sig { returns(T.nilable(String)) }
  attr_reader :path_link

  sig { returns(T::Boolean) }
  attr_reader :is_alert_closed

  sig { returns(Repository) }
  attr_reader :repository

  sig do
    params(
      create_pr_path: String,
      suggested_fix: Turboscan::Proto::SuggestedFix,
      generated_at: T.untyped,
      repository: Repository,
      alert_location: T.untyped,
      alert_number: Integer,
      alert_title: String,
      alert_description_html: String,
      alert_code_paths_url: T.nilable(String),
      alert_rule_severity: T.nilable(Symbol),
      alert_help_html: T.nilable(String),
      alert_tool_name: T.nilable(String),
      path_link: T.nilable(String),
      is_alert_closed: T::Boolean
    ).void
  end
  def initialize(
    create_pr_path:,
    suggested_fix:,
    generated_at:,
    repository:,
    alert_location:,
    alert_number:,
    alert_title:,
    alert_description_html:,
    alert_code_paths_url: nil,
    alert_rule_severity: nil,
    alert_help_html: nil,
    alert_tool_name: nil,
    path_link: nil,
    is_alert_closed: false
  )
    @create_pr_path = create_pr_path
    @suggested_fix = suggested_fix
    @generated_at = generated_at
    @repository = repository
    @alert_location = alert_location
    @alert_number = alert_number
    @alert_title = alert_title
    @alert_description_html = alert_description_html
    @alert_code_paths_url = alert_code_paths_url
    @alert_rule_severity = alert_rule_severity
    @alert_help_html = alert_help_html
    @alert_tool_name = alert_tool_name
    @path_link = path_link
    @is_alert_closed = is_alert_closed
  end

  # Returns the diff entries so the one matching the alert location is first.
  memoize def suggested_fix_diff_entries
    current_diff_entry = T.let(nil, T.untyped)
    out = parsed_diff_entries.reject do |diff_entry|
      if diff_entry.path == alert_location&.file_path
        current_diff_entry = diff_entry
        true
      else
        false
      end
    end

    out.unshift(current_diff_entry) if current_diff_entry

    out
  end

  memoize def suggested_fix_file_highlighting
    suggested_fix_diff_entries.each_with_object({}) do |diff_entry, out|
      out[diff_entry.path] = DiffEntryHighlighting.new(diff_entry).highlight_lines
    end
  end

  memoize def suggested_fix_description
    GitHub::Goomba::MarkdownPipeline.to_html(suggested_fix.description)
  end

  def suggested_fix_dependency_metadata
    suggested_fix.dependency_metadata
  end

  def is_from_thirdparty_tool?
    CodeScanning::AutofixThirdPartyTools.is_supported_tool?(alert_tool_name)
  end

  def autofix_docs_url
    return DocsUrlConfig.url_for("about-autofix") unless is_from_thirdparty_tool?
    CodeScanning::AutofixThirdPartyTools.changelog_url
  end

  def disable_suggested_fix_button?
    !repository.pushable_by?(current_user)
  end

  def create_branch_dialog_props
    {
      alertNumbers: [alert_number],
      alertNumbersWithSuggestedFixes: [alert_number],
      firstAlertWithSuggestedFixTitle: alert_title,
      repository: {
        name: repository.name,
        ownerLogin: repository.owner&.display_login,
        path: repository.path,
        typeIcon: repository.repo_type_icon
      },
      createPath: create_pr_path,
      someSelectedAlertsAreClosed: is_alert_closed,
      isCampaign: false
    }
  end

  private

  def parsed_diff_entries
    CodeScanning::AutofixSuggestion.new(suggested_fix).diff_entries
  end
end
