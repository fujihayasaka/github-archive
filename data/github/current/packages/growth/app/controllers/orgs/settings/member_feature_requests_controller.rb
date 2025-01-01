# typed: strict
# frozen_string_literal: true

class Orgs::Settings::MemberFeatureRequestsController < Orgs::Controller
  include MemberFeatureRequestsHelper

  before_action :dotcom_required
  before_action :login_required
  before_action :non_emu_required
  before_action :require_billing_manageable
  before_action :mark_request_a_feature_notifications_as_read, only: [:show]

  stylesheet_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:show]

  sig { void }
  def show
    total_by_feature, total_by_addons = MemberFeatureRequest
      .total_by_feature(this_organization)
      .partition { |feature, _|  !feature.add_on? }
      .map { |partition| partition.sort_by(&:last).reverse.to_h }  # sort by total requests
    total_members_requesting = MemberFeatureRequest.total_members_requesting_features(this_organization)
    enterprise_only = total_by_feature&.keys&.any? { |feature| feature.enterprise_only? }
    ActiveRecord::Base.connected_to(role: :writing) { user_visited_feature_request_page!(this_organization, current_user) }

    render "settings/organization/member_feature_requests/show", locals: {
      enterprise_only: enterprise_only,
      total_by_feature: total_by_feature,
      total_by_addons: total_by_addons,
      total_members_requesting: total_members_requesting,
    }
  end

  private

  sig { void }
  def mark_request_a_feature_notifications_as_read
    async_mark_threads_as_read(user_member_feature_requests) unless user_member_feature_requests.empty?
  end

  sig { returns(ActiveRecord::Relation) }
  def user_member_feature_requests
    MemberFeatureRequest::Notification.where(entity: this_organization, user: current_user)
  end

  sig { void }
  def require_billing_manageable
    render_404 unless org_billing_manageable?(this_organization)
  end
end
