# typed: true
# frozen_string_literal: true

module Orgs
  module AuditLog
    class TipView < ::AuditLog::TipView
      attr_reader :organization

      def selected_tip
        render_link(tips.sample) do |components|
          urls.settings_org_audit_log_path(organization, q: Search::Queries::AuditLogQuery.stringify(components))
        end
      end
    end
  end
end
