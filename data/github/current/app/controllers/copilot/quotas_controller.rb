# typed: true
# frozen_string_literal: true

class Copilot::QuotasController < ApplicationController
  before_action :login_required
  before_action :dotcom_required
  before_action :require_feature_enabled

  def show
    context_region_title "Copilot Quotas Settings"

    if this_user.nil?
      render "copilot/quotas/show_invalid" and return
    end

    copilot_user = Copilot::User.new(this_user)
    limited_user = Copilot::LimitedUser.for_subscribed_user(this_user)

    if limited_user.nil?
      render "copilot/quotas/show_unsubscribed" and return
    end

    render "copilot/quotas/show", locals: {
      this_user: this_user,
      limited_user: limited_user,
      copilot_user: copilot_user,
    }
  end

  def update
    if this_user.nil?
      flash[:error] = "Cannot find a user with that login #{params[:user_id]}"
      render "copilot/quotas/show_invalid" and return
    end

    GitHub.logger.with_named_tags(
      "gh.copilot.quota.mode": params[:mode].to_s,
      "gh.user.id": this_user.id,
    ) do
      copilot_user = Copilot::User.new(this_user)

      if params[:mode] == "subscribe"
        GitHub.flipper[:copilot_quota_testing].enable(this_user)
      end

      limited_user = ::Copilot::LimitedUser.find_by(user_id: copilot_user.id)

      if limited_user.nil?
        GitHub.logger.info("User is not a subscribed Copilot Limited User")
        flash[:error] = "User is not a subscribed Copilot Limited User"
        render "copilot/quotas/show_invalid" and return
      end

      luser = T.must(limited_user)

      case params[:mode]
      when "destroy"
        luser.destroy!
        copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
        flash[:notice] = "Destroyed Copilot Limited User Record"
      when "upgrade_complimentary"
        GitHub.logger.info("Upgrading Copilot Limited User to complimentary")
        luser.destroy
        free_user = Copilot::FreeUser.create(
          user_id: copilot_user.id,
          free_user_type: Copilot::FreeUser::COMPLIMENTARY_ACCESS.name,
          last_checked_date: 1.year.from_now.to_date,
        )
        if free_user.valid?
          free_result = copilot_user.subscribe_free_user
          if free_result.ok?
            flash[:notice] = "Upgraded Copilot Limited User to complimentary"
            copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
          else
            flash[:error] = "Failed to upgrade Copilot Limited User to complimentary: #{free_result.error}"
          end
        else
          flash[:error] = "Failed to upgrade Copilot Limited User to complimentary"
        end
      when "quotas"
        if params[:quotas].present?
          GitHub.logger.info("Updating quotas")
          params[:quotas].each do |quota, value|
            GitHub.logger.info("Setting quota", "gh.copilot.quota.feature": quota, "gh.copilot.quota.value": value)
            result = luser.set_quota_remaining(feature: quota, quota: value.to_i)
            unless result.ok?
              GitHub.logger.error("Failed to update quota", "gh.copilot.quota.feature": quota, "gh.copilot.quota.value": value, "gh.copilot.quota.error": result.error)
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
