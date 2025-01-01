
# typed: true
# frozen_string_literal: true

class Memexes::NotificationSubscriptionsController < Memexes::Controller

  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :require_verified_email
  before_action :require_memex_feature_enabled
  before_action :require_this_memex
  before_action :user_has_read_access
  before_action :require_memex_status_updates_notifications

  allow_verified_fetch

  def create
    return head :no_content if notifyd_subscription.subscribe.value

    head :internal_server_error
  end

  def destroy
    return head :no_content if notifyd_subscription.unsubscribe.value

    head :internal_server_error
  end

  private

  sig { returns(MemexProject::NotifydSubscriptions) }
  memoize def notifyd_subscription
    MemexProject::NotifydSubscriptions.new(current_user, this_memex)
  end

  def require_memex_status_updates_notifications
    render_404 unless memex_status_updates_notifications_enabled?
  end
end
