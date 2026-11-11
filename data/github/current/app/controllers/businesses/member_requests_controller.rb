# typed: strict
# frozen_string_literal: true

# Enterprise-level "Requests from members" page: aggregates member feature
# requests billed to the business (enterprise-billed Copilot add-ons and
# additional Copilot budget) across its member organizations.
class Businesses::MemberRequestsController < Businesses::BusinessController
  before_action :login_required
  before_action :dotcom_required
  before_action :member_requests_available_required
  before_action :business_access_required # enterprise owners + billing managers
  before_action :non_emu_business_required
  before_action :feature_flag_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:show]

  # Counts and amounts are aggregated in SQL; full rows are only hydrated for
  # a bounded recent window used for the decorative parts of each row
  # (requester avatars, "Requested in <orgs>").
  RECENT_REQUESTS_PREVIEW_LIMIT = 100

  sig { void }
  def show
    business_requests = MemberFeatureRequest.requested_business_requests(this_business)

    addon_scope = business_requests.where(request_type: :feature_unlock)
    recent_addon_requests = addon_scope
      .includes(:request_entity, :requester)
      .order(created_at: :desc)
      .limit(RECENT_REQUESTS_PREVIEW_LIMIT)
      .group_by(&:feature)
    addon_requests = addon_scope
      .group(:feature).count
      .sort_by { |_, count| -count }
      .to_h { |feature, count| [feature, { count: count, recent: recent_addon_requests.fetch(feature, []) }] }

    budget_scope = business_requests.where(request_type: :additional_budget)
    budget_totals_by_org_id = budget_scope.group(:request_entity_id).sum(:requested_amount_cents)
    budget_requester_counts_by_org_id = budget_scope.group(:request_entity_id).distinct.count(:requester_id)
    recent_budget_requests = budget_scope
      .includes(:requester)
      .order(created_at: :desc)
      .limit(RECENT_REQUESTS_PREVIEW_LIMIT)
      .group_by(&:request_entity_id)
    organizations_by_id = Organization.where(id: budget_totals_by_org_id.keys).index_by(&:id)
    budget_rows = budget_totals_by_org_id.sort_by { |_, total_cents| -total_cents }.filter_map do |org_id, total_cents|
      organization = organizations_by_id[org_id]
      next unless organization

      [organization, {
        total_cents: total_cents,
        requester_count: budget_requester_counts_by_org_id.fetch(org_id, 0),
        recent: recent_budget_requests.fetch(org_id, []),
      }]
    end
    budget_requests_by_org = budget_rows.to_h

    render "businesses/member_requests/show", locals: {
      addon_requests: addon_requests,
      budget_requests_by_org: budget_requests_by_org,
    }
  end

  private

  sig { void }
  def member_requests_available_required
    render_404 if MemberFeatureRequest.unavailable?(user: current_user)
  end

  sig { void }
  def non_emu_business_required
    render_404 if this_business.enterprise_managed_user_enabled?
  end

  sig { void }
  def feature_flag_required
    render_404 unless this_business.feature_flag_enabled?(:enterprise_member_requests, default: false)
  end
end
