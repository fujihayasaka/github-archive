# typed: true
# frozen_string_literal: true

class Copilot::QuotasController < ApplicationController
  before_action :login_required
  before_action :dotcom_required
  before_action :require_feature_enabled

  def show
    context_region_title "Copilot Quotas Settings"

    if this_user.nil?
      flash[:error] = "Cannot find a user with that login #{params[:user_id]}"
      render "copilot/quotas/show_invalid" and return
    end

    if !this_user.feature_enabled?(:copilot_free_limited_user)
      flash[:error] = "This user is not in the feature flag 'copilot_free_limited_user'"
      render "copilot/quotas/show_invalid" and return
    end

    copilot_user = Copilot::User.new(this_user)
    limited_user = Copilot::LimitedUser.find_for_copilot_user(copilot_user)

    if limited_user.present? && !T.must(limited_user).subscribed?
      flash[:error] = "User is not a subscribed Copilot Limited User"
    end

    render "copilot/quotas/show", locals: {
      this_user: this_user,
      limited_user: limited_user,
    }
  end

  def update
    if this_user.nil?
      flash[:error] = "Cannot find a user with that login #{params[:user_id]}"
      render "copilot/quotas/show_invalid" and return
    end

    copilot_user = Copilot::User.new(this_user)

    limited_user = ::Copilot::LimitedUser.find_for_copilot_user(copilot_user)

    if limited_user.nil?
      flash[:error] = "User is not a subscribed Copilot Limited User"
      render "copilot/quotas/show_invalid" and return
    end

    luser = T.must(limited_user)

    case params[:mode]
    when "subscribe"
      luser.subscribe
      flash[:notice] = "Subscribed Copilot Limited User"
    when "unsubscribe"
      luser.subscribed_at = nil
      luser.save
      flash[:notice] = "Unsubscribed Copilot Limited User"
    when "quotas"
      if params[:quotas].present?
        params[:quotas].each do |quota, value|
          result = luser.set_quota_remaining(feature: quota, quota: value.to_i)
          unless result.ok?
            flash[:error] = "Cannot update quota for #{quota}"
            break
          end
        end
        flash[:notice] = "Updated dem quotas"
      else
        flash[:error] = "No quotas to update"
      end
    else
      flash[:error] = "Unknown mode #{params[:mode]}"
    end


    redirect_to copilot_quota_path(this_user)
  end

  private

  memoize def this_user
    User.find_by(type: "User", login: params[:user_id])
  end

  def target_for_conditional_access
    logged_in? ? current_user : :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def resource_for_conditional_access
    logged_in? ? current_user : :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  def ensure_not_proxima
    render_404 if GitHub.multi_tenant_enterprise?
  end

  def require_feature_enabled
    return if GitHub.flipper[:copilot_quota_testing].enabled? # this means it's globally shipped
    return if current_user&.feature_enabled?(:copilot_quota_testing) # this means it's enabled for the user

    render_404
  end

end
