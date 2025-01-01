# typed: true
# frozen_string_literal: true

module SlashCommands
  class AlertsCommand < ApplicationSlashCommand
    ALERT_TYPES = {
      note: "NOTE",
      tip: "TIP",
      important: "IMPORTANT",
      warning: "WARNING",
      caution: "CAUTION",
    }

    category :markdown

    trigger_on name: "alerts", title: "Alerts", description: "Add a markdown alert to emphasize important information"

    menu :alert_type
    fill :markdown

    def alert_type
      alerts = []
      ALERT_TYPES.each do |id, value|
        alerts.push(Item.new(id: id.to_s, text: value.humanize, value: id))
      end

      menu(:alert_type, items: alerts)
    end

    def markdown
      ActiveSupport::SafeBuffer.new <<~MARKDOWN
        > [!#{ALERT_TYPES[data[:alert_type]&.to_sym]}]
        > %cursor%
      MARKDOWN
    end
  end
end
