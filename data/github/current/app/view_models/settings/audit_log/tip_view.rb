# typed: true
# frozen_string_literal: true

module Settings
  module AuditLog
    class TipView < ::AuditLog::TipView
      def tips
        tips = [
          "View all events created yesterday created:#{24.hours.ago.strftime("%Y-%m-%d")}",
          "View all events where you created something operation:create",
        ]

        tips
      end

      def selected_tip
        render_link(tips.sample) do |components|
          urls.settings_user_audit_log_path(q: Search::Queries::AuditLogQuery.stringify(components))
        end
      end
    end
  end
end
