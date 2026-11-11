# typed: true
# frozen_string_literal: true

class Users::StaffAccessRequestsController < ApplicationController
  before_action :login_required
  before_action :ensure_request_is_for_current_user
  before_action :ensure_request_is_active

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    render "users/staff_access_requests/show"
  end

  def accept # rubocop:todo GitHub/UseRestfulActions
    grant = current_request.accept(current_user)

    if grant
      StaffAccessMailer.impersonation_request_accepted(grant).deliver_later
      flash[:notice] = "You have granted GitHub staff access to login as your account until #{grant.expires_at.to_date}."
    end

    redirect_to settings_path
  end

  def deny # rubocop:todo GitHub/UseRestfulActions
    current_request.deny(current_user)
    StaffAccessMailer.impersonation_request_denied(current_request).deliver_later
    flash[:notice] = "You have denied GitHub staff's request to login as your account."
    redirect_to settings_path
  end

  private

  # Okay to skip CAP here - this is only for users operating on their own account (agree/reject staff impersonation).
  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  helper_method :current_request
  memoize def current_request
    StaffAccessRequest.find(params[:id])
  end

  def ensure_request_is_for_current_user
    unless current_request.accessible == current_user
      render_404
    end
  end

  def ensure_request_is_active
    unless current_request.active?
      flash[:error] = StaffAccessRequest::REQUEST_NOT_ACTIVE_MESSAGE
      redirect_to settings_path
    end
  end
end
