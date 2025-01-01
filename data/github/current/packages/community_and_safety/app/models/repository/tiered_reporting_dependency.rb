# typed: false
# frozen_string_literal: true

module Repository::TieredReportingDependency
  extend ActiveSupport::Concern
  include Configurable::TieredReporting
  include Configurable::TieredReportingAllUsers

  # True if we're not on enterprise and the repo is owned by an org
  def eligible_for_tiered_reporting?
    GitHub.can_report? && owner.organization? && !private?
  end

  # True if repo is eligible for this feature and the actor is an admin
  def can_access_tiered_reporting?(actor)
    eligible_for_tiered_reporting? && adminable_by?(actor)
  end

  # True if the user can access TR and we're not in a private repo
  def can_enable_tiered_reporting?(actor)
    can_access_tiered_reporting?(actor)
  end

  def show_abuse_report_banner?(viewer)
    (tiered_reporting_explicitly_enabled? || tiered_reporting_all_users_explicitly_enabled?) && adminable_by?(viewer) && unresolved_abuse_report_count > 0
  end

  def unresolved_abuse_report_count
    return @unresolved_abuse_report_count unless @unresolved_abuse_report_count.nil?
    reports = AbuseReport.for_repository_maintainer(repository.id).where(resolved: false, user_hidden: false).reject(&:content_spammy?)
    @unresolved_abuse_report_count = reports.count { |report| report.reported_content.present? }
  end
end
