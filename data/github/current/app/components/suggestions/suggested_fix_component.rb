# typed: true
# frozen_string_literal: true

class Suggestions::SuggestedFixComponent < ApplicationComponent
  extend T::Sig

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
  attr_reader :path_link

  sig do
    params(
      create_pr_path: String,
      suggested_fix: Turboscan::Proto::SuggestedFix,
      generated_at: T.untyped,
      alert_location: T.untyped,
      alert_title: String,
      alert_description_html: String,
      alert_code_paths_url: T.nilable(String),
      alert_rule_severity: T.nilable(Symbol),
      alert_help_html: T.nilable(String),
      path_link: T.nilable(String),
    ).void
  end
  def initialize(
    create_pr_path:,
    suggested_fix:,
    generated_at:,
    alert_location:,
    alert_title:,
    alert_description_html:,
    alert_code_paths_url: nil,
    alert_rule_severity: nil,
    alert_help_html: nil,
    path_link: nil
  )
    @create_pr_path = create_pr_path
    @suggested_fix = suggested_fix
    @generated_at = generated_at
    @alert_location = alert_location
    @alert_title = alert_title
    @alert_description_html = alert_description_html
    @alert_code_paths_url = alert_code_paths_url
    @alert_rule_severity = alert_rule_severity
    @alert_help_html = alert_help_html
    @path_link = path_link
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

  private

  def parsed_diff_entries
    suggested_fix.files.each_with_object([]) do |file, out|
      begin
        parser = GitHub::Diff::Parser.new(file.diff_content)
        parser.each { |entry| out << entry }
      rescue GitHub::Diff::Parser::UnrecognizedText => err
        # report the error to Sentry
        Failbot.report!(err)
        []
      end
    end
  end
end
