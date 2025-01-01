# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::HealthChecksController < Stafftools::SponsorsController
  before_action :sponsors_listing_required

  depends_on_clusters ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    render "stafftools/sponsors/members/health_checks/index", locals: {
      public_contribution_count: this_listing.public_contribution_count,
      abuse_report_count: this_sponsorable.received_abuse_reports.count,
      follower_count: this_sponsorable.followers_count(viewer: current_user),
      blocked_by_count: this_sponsorable.ignored_by_users.count,
      has_trade_restrictions: this_sponsorable.has_sdn_auto_sponsorable_restrictions?,
      trade_screening_status: this_sponsorable.trade_screening_status,
      signup_time: this_sponsorable.created_at,
      recently_created_github_account: this_listing.recently_created_github_account?,
      is_user: this_sponsorable.user?,
      timezone_matches_country_of_residence: this_listing.sponsorable_timezone_matches_country_of_residence?,
      time_zone_name: this_sponsorable.time_zone_name,
      has_supported_timezone: this_listing.sponsorable_has_supported_timezone?,
      country_of_residence: this_listing.country_of_residence,
      has_public_non_fork_repository: this_listing.sponsorable_has_public_non_fork_repository?,
      has_customized_user_profile: this_listing.sponsorable_has_customized_user_profile?,
    }, layout: false
  end
end
