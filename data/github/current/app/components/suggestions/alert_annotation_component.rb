# typed: strict
# frozen_string_literal: true

class Suggestions::AlertAnnotationComponent < ApplicationComponent
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

  sig do
    params(
      alert_title: String,
      alert_description_html: String,
      alert_code_paths_url: T.nilable(String),
      alert_rule_severity: T.nilable(Symbol),
      alert_help_html: T.nilable(String),
    ).void
  end
  def initialize(
    alert_title:,
    alert_description_html:,
    alert_code_paths_url: nil,
    alert_rule_severity: nil,
    alert_help_html: nil
  )
    @alert_title = alert_title
    @alert_description_html = alert_description_html
    @alert_code_paths_url = alert_code_paths_url
    @alert_rule_severity = alert_rule_severity
    @alert_help_html = alert_help_html
  end

  sig { returns(String) }
  def alert_annotation_border_class
    class_names(
      "color-border-default": alert_rule_severity == :NOTE,
      "code-scanning-alert-warning-message": alert_rule_severity == :WARNING,
      "color-border-danger-emphasis": alert_rule_severity == :ERROR,
    )
  end

  sig { returns(String) }
  def alert_annotation_severity_color_class
    class_names(
      "color-fg-muted": alert_rule_severity == :NOTE,
      "color-fg-attention": alert_rule_severity == :WARNING,
      "color-fg-danger": alert_rule_severity == :ERROR,
    )
  end

  sig { returns(String) }
  def alert_annotation_octicon
    {
      NOTE: "note",
      WARNING: "alert",
      ERROR: "circle-slash",
    }[alert_rule_severity] || "info"
  end
end
