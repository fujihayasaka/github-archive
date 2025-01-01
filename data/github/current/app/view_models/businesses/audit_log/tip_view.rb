# typed: true
# frozen_string_literal: true

class Businesses::AuditLog::TipView < ::AuditLog::TipView
  attr_reader :business

  def initialize(**args)
    super(args)
    @business = args[:business]
  end

  def selected_tip
    render_link(tips.sample) do |components|
      urls.settings_audit_log_enterprise_path \
        business.slug,
        q: Search::Queries::AuditLogQuery.stringify(components)
    end
  end
end
