# typed: true
# frozen_string_literal: true

module CodeScanning
  module AlertDependency
    include TextHelper

    def alert_title(alert)
      if alert.rule&.short_description.present?
        alert.rule.short_description
      else
        alert_message_text(alert)
      end
    end

    def alert_message_text(alert)
      html = GitHub::Goomba::MarkdownPipeline.to_html(alert.message_text)
      strip_tags_and_collapse_whitespace(html)
    end
  end
end
