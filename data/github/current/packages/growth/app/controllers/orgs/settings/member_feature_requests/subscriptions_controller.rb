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
    notification_subscription.all!

    GitHub.dogstats.increment("member_feature_request_notification_subscription", tags: ["subscribed"])

    if notifyd_member_feature_request_settings(notification_subscription).save
      render json: { success: true }, status: :ok
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  sig { void }
  def update
    if params[:features].nil?
      notification_subscription.ignore!
    else
      notification_subscription.custom!(features: params[:features])
    end

    GitHub.dogstats.increment("member_feature_request_notification_subscription", tags: ["custom"])

    if notifyd_member_feature_request_settings(notification_subscription).save
      render json: { success: true }, status: :ok
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  sig { void }
  def destroy
    notification_subscription.ignore!

    GitHub.dogstats.increment("member_feature_request_notification_subscription", tags: ["ignore"])

    if notifyd_member_feature_request_settings(notification_subscription).save
      render json: { success: true }, status: :ok
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  private

  sig { returns(MemberFeatureRequest::Notification::Setting) }
  memoize def notification_subscription
    MemberFeatureRequest::Notification::Setting.new(user_enabled: true)
  end

  sig { params(subscription: MemberFeatureRequest::Notification::Setting).returns(Notifyd::MemberFeatureRequestSettings) }
  def notifyd_member_feature_request_settings(subscription)
    Notifyd::MemberFeatureRequestSettings.new(
      user: current_user,
      organization_id: this_organization.id,
      subscription: notification_subscription
    )
  end

  sig { void }
  def require_billing_manageable
    render_404 unless org_billing_manageable?(this_organization)
  end
end
