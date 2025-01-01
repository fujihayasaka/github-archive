# typed: strict
# frozen_string_literal: true

class Orgs::Settings::MemberFeatureRequests::SubscriptionsController < Orgs::Controller
  include MemberFeatureRequestsHelper

  before_action :dotcom_required
  before_action :login_required
  before_action :non_emu_required
  before_action :require_billing_manageable

  sig { void }
  def create
    GitHub.dogstats.increment("member_feature_request_notification_subscription", tags: ["subscribed"])

    settings = ::Notifications::Settings::MemberFeatureRequestsSettings.new(
      features: MemberFeatureRequest::Feature.values,
    )
    if ::Notifications::Settings.set_member_feature_requests(current_user, this_organization.id, settings)
      render json: { success: true }, status: :ok
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  sig { void }
  def update
    GitHub.dogstats.increment("member_feature_request_notification_subscription", tags: ["custom"])

    features = (params[:features] || []).filter_map do |feature|
      MemberFeatureRequest::Feature.from_string(feature)
    end
    settings = Notifications::Settings::MemberFeatureRequestsSettings.new(features:)
    if Notifications::Settings.set_member_feature_requests(current_user, this_organization.id, settings)
      render json: { success: true }, status: :ok
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  sig { void }
  def destroy
    GitHub.dogstats.increment("member_feature_request_notification_subscription", tags: ["ignore"])

    settings = Notifications::Settings::MemberFeatureRequestsSettings.new(features: [])
    if Notifications::Settings.set_member_feature_requests(current_user, this_organization.id, settings)
      render json: { success: true }, status: :ok
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  private

  sig { void }
  def require_billing_manageable
    render_404 unless org_billing_manageable?(this_organization)
  end
end
