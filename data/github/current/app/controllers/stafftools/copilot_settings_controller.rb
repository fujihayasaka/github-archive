# typed: strict
# frozen_string_literal: true

class Stafftools::CopilotSettingsController < StafftoolsController
  include CopilotBlockHelper
  layout "layouts/stafftools/user/content"

  before_action :dotcom_required
  before_action :entity_required
  before_action :ensure_user_exists
  before_action :ensure_org_not_user, only: [:update_plan]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show, :refresh_cache]

  sig { void }
  def show
    if this_user.organization?
      render "stafftools/copilot_settings/show_organization", locals: {
        copilot_organization: Copilot::Organization.new(this_user),
        copilot_seat_emissions: Copilot::SeatEmission.for_owner(this_user).order(occurred_at: :desc).paginate(
          page: params[:seat_emissions_page] || 1,
          per_page: 10,
        ),
        business_trial: Copilot::BusinessTrial.for_organization(this_user),
        can_emit_usage: Copilot::SeatEmission.can_emit?(this_user),
      }
    else
      copilot_user           = Copilot::User.new(this_user)
      copilot_auth           = Copilot::Authorizer.new(copilot_user)
      copilot_auth_no_snippy = Copilot::Authorizer.new(copilot_user, include_snippy: false)
      engaged_oss_user       = Copilot::EngagedOssUser.where(user: copilot_user.user_object).first
      free_user              = Copilot::FreeUser.find_for_copilot_user(copilot_user)
      limited_user           = Copilot::LimitedUser.find_by(user: copilot_user.user_object)
      coupon                 = copilot_user.user_object.coupon
      seats                  = Copilot::Seat.for_user(this_user).to_a
      partner_orgs = if copilot_user.is_partner_user?
        copilot_user.partner_orgs.map(&:organization_object).map(&:display_login)
      else
        []
      end

      render "stafftools/copilot_settings/show", locals: {
        copilot_user: copilot_user,
        copilot_auth: copilot_auth,
        copilot_auth_no_snippy: copilot_auth_no_snippy,
        engaged_oss_user: engaged_oss_user,
        free_user: free_user,
        coupon: coupon,
        seats: seats,
        partner_orgs: partner_orgs,
        limited_user: limited_user,
      }
    end
  end

  sig { void }
  def create
    complimentary_access_reason = params[:complimentary_access_reason]

    if complimentary_access_reason.blank?
      flash[:error] = "Please select a reason for complimentary access"
      redirect_to stafftools_user_copilot_settings_path(this_user) and return
    end

    case complimentary_access_reason
    when "y_combinator"
      create_free_user(
        Copilot::FreeUser::Y_COMBINATOR,
        cancel_subscription: true,
        last_checked_date: 1.year.from_now.to_date,
        complimentary_access_reason_explanation: "y_combinator",
      )

      flash[:notice] = "YCombinator Free User created"
      redirect_to stafftools_user_copilot_settings_path(this_user) and return
    when "complimentary_access"
      complimentary_access_duration = params[:complimentary_access_duration]

      if complimentary_access_duration.blank?
        flash[:error] = "Please select a duration for complimentary access"
        redirect_to stafftools_user_copilot_settings_path(this_user) and return
      end

      complimentary_access_reason_explanation = params[:complimentary_access_reason_explanation]

      if complimentary_access_reason_explanation.blank?
        flash[:error] = "Please enter an explanation for complimentary access"
        redirect_to stafftools_user_copilot_settings_path(this_user) and return
      end

      case complimentary_access_duration
      when "unlimited"
        create_free_user(
          Copilot::FreeUser::COMPLIMENTARY_ACCESS,
          cancel_subscription: true,
          last_checked_date: Date.new(9999, 12, 31),
          complimentary_access_reason_explanation: complimentary_access_reason_explanation,
        )
      when "specified"
        month = params[:complimentary_access_duration_month].to_i
        day   = params[:complimentary_access_duration_day].to_i
        year  = params[:complimentary_access_duration_year].to_i

        date = Date.today

        begin
          date = Date.new(year, month, day)
        rescue Date::Error => exception
          flash[:error] = "Invalid date: #{exception.message}"
          redirect_to stafftools_user_copilot_settings_path(this_user) and return
        end

        create_free_user(
          Copilot::FreeUser::COMPLIMENTARY_ACCESS,
          cancel_subscription: true,
          last_checked_date: date,
          complimentary_access_reason_explanation: complimentary_access_reason_explanation,
        )
      else
        flash[:error] = "Invalid complimentary access duration"
        redirect_to stafftools_user_copilot_settings_path(this_user) and return
      end

      flash[:notice] = "Complimentary User created"
      redirect_to stafftools_user_copilot_settings_path(this_user) and return
    else
      flash[:error] = "Unknown complimentary access reason"
      redirect_to stafftools_user_copilot_settings_path(this_user) and return
    end
  end

  sig { void }
  def destroy
    remove_access_reason_explanation = params[:remove_access_reason_explanation]

    if remove_access_reason_explanation.blank?
      flash[:error] = "Please enter a reason for removing complimentary access"
      redirect_to stafftools_user_copilot_settings_path(this_user) and return
    end

    copilot_user           = Copilot::User.new(this_user)
    free_user              = Copilot::FreeUser.find_for_copilot_user(copilot_user)

    if free_user
      Rails.logger.info("Removing complimentary access for user #{this_user.id} with reason: #{remove_access_reason_explanation}")

      # block them from using a coupon
      if free_user.type.coupon_based
        Rails.logger.info("Blocking coupon user from using coupon to signup for free")
        copilot_user.free_user_block!
      end

      free_user_type = free_user.free_user_type
      free_user.destroy! # remove the record

      Copilot::Instrumenter.instrument_free_access_removed(
        this_user,
        current_user,
        free_user_type,
        remove_access_reason_explanation,
      )

      flash[:notice] = "Free user destroyed"
    else
      flash[:error] = "Free user not found"
    end
    redirect_to stafftools_user_copilot_settings_path(this_user) and return
  end

  sig { void }
  def generate_csv # rubocop:todo GitHub/UseRestfulActions
    copilot_organization = ::Copilot::Organization.new(this_user)
    GitHub.dogstats.increment "copilot.stafftools.org.generate_csv"
    GitHub.logger.info("Generating CSV in Organization Stafftools", "gh.org.id" => copilot_organization.id, "gh.user.id" => current_user.id)
    send_data copilot_organization.to_csv, filename: "#{this_user.display_login.parameterize}-seat-usage-#{Time.current.to_i}.csv"
  end

  sig { void }
  def generate_activity_csv # rubocop:todo GitHub/UseRestfulActions
    copilot_organization = ::Copilot::Organization.new(this_user)
    GitHub.dogstats.increment "copilot.stafftools.org.generate_activity_csv"
    GitHub.logger.info("Generating Activity CSV in Organization Stafftools", "gh.org.id" => copilot_organization.id, "gh.user.id" => current_user.id)

    ::Copilot::ActivityReportJob.perform_later(
      entity_type: "organization",
      entity_id: copilot_organization.id,
      actor_id: current_user.id
    )
    flash[:success] = "We're preparing a Copilot Activity Report for #{this_user.display_login}. It may take a few minutes to generate, and we'll send you an email when it's ready."
    redirect_to  stafftools_user_copilot_settings_path(this_user)
  end

  sig { void }
  def refresh_organization_cache # rubocop:todo GitHub/UseRestfulActions
    flash[:notice] = "A background job has been started to refresh users Copilot settings cache"
    Copilot::BatchUpdateUserSettingsJob.perform_later(this_user.id)
    redirect_to stafftools_user_copilot_settings_path(this_user)
  end

  sig { void }
  def auth_and_capture  # rubocop:todo GitHub/UseRestfulActions
    copilot_entity = if this_user.organization?
      Copilot::Organization.new(this_user)
    else
      Copilot::User.new(this_user)
    end

    copilot_entity.perform_auth_and_capture!(skip_previous_authorizations_check: true, audit_log_reason: "stafftools")

    GitHub.logger.info(
      "Copilot auth and capture triggered by stafftools",
      "gh.user.login" => this_user,
      "gh.actor.login" => current_user,
    )
    flash[:notice] = "Authorization check triggered. You may need to refresh the page"

    redirect_to stafftools_user_copilot_settings_path(this_user)
  end

  sig { void }
  def administrative_block  # rubocop:todo GitHub/UseRestfulActions
    copilot_user = Copilot::User.new(this_user)
    action = :block
    reason = params[:reason].to_s

    if copilot_user.administrative_blocked?
      # we are unblocking here
      action = :unblock
      reason = prefix_reason(reason, "unblock")
      flash[:notice] = "Copilot administrative block removed"
      # unblock account and payment method if specified
      copilot_user.administrative_unblock!(current_user, reason, unblock_payment_method: !!params[:unblock_payment_method])
    else
      reason = prefix_reason(reason, params[:block_option].to_s)
      flash[:notice] = "Copilot administrative block created"
      # We allow blocking hammy users if it's done one-by-one by a person in Stafftools
      copilot_user.administrative_block!(
        current_user,
        reason,
        skip_hammy_check: true,
        send_block_email: reason.start_with?(WARN_VIA_SUPPORT),
        superban: reason.start_with?(SUPERBAN),
      )
    end

    GitHub.logger.info(
      "Copilot administrative #{action}",
      "gh.copilot.admin_block.action" => action,
      "gh.copilot.admin_block.reason" => reason,
      "gh.user.login" => this_user,
      "gh.actor.login" => current_user,
    )

    redirect_to stafftools_user_copilot_settings_path(this_user)
  end

  sig { void }
  def warn_via_sire # rubocop:todo GitHub/UseRestfulActions
    copilot_user = Copilot::User.new(this_user)
    reason = params[:warn_reason].to_s
    if copilot_user.has_been_warned?
      flash[:error] = "User already has been notified via SIRE"
      redirect_to stafftools_user_copilot_settings_path(this_user)
    else
      reference_number = SecureRandom.uuid
      GitHub.logger.info(
        "Warning user via SIRE",
        "gh.copilot.warn.reason" => reason,
        "gh.user.login" => this_user,
        "gh.actor.login" => current_user,
        "gh.copilot.warn.reference_number" => reference_number,
      )
      # this just stores in the AdministrativeBlock table that they were warned
      copilot_user.warn_user!(
        current_user,
        reference_number,
        reason + " (SIRE reference number: #{reference_number})",
      )

      # create actions
      incident_response_user_actions = {
        users: [{ id: this_user.id }],
        staffnote: "notifying user of potential Copilot access revocation",
        notify: {
          from: "support@githubsupport.com",
          subject: "Regarding Your Copilot Access",
          template: Copilot.warn_email
        }
      }

      SecurityIncidentResponseJob.perform_later(
        actor: current_user,
        id: reference_number,
        incident_responses: [
          incident_response_user_actions
        ]
      )

      flash[:notice] = "Notification submitted to SIRE (#{reference_number})"
      redirect_to stafftools_user_copilot_settings_path(this_user)
    end
  end

  sig { void }
  def toggle_email_notifications # rubocop:todo GitHub/UseRestfulActions
    redirect_to stafftools_user_copilot_settings_path(this_user) and return unless this_user.is_a?(Organization)

    # rubocop:disable GitHub/FeatureManagement/NoActorFeatureFlagManipulation
    if params[:notifications].present?
      if params[:notifications] == "enabled"
        this_user.enable_feature_flag(:copilot_communication_opt_out)
        result = "disabled"
      elsif params[:notifications] == "disabled"
        this_user.disable_feature_flag(:copilot_communication_opt_out)
        result = "enabled"
      end
    else
      if Copilot.copilot_communication_opt_out?(this_user)
        this_user.disable_feature_flag(:copilot_communication_opt_out)
        result = "enabled"
      else
        this_user.enable_feature_flag(:copilot_communication_opt_out)
        result = "disabled"
      end
    end
    # rubocop:enable GitHub/FeatureManagement/NoActorFeatureFlagManipulation

    GitHub.logger.info(
      "Copilot email notifications #{result} via stafftools",
      "gh.user.login" => this_user,
      "gh.actor.login" => current_user,
    )

    flash[:notice] = "Copilot email notifications #{result} for #{this_user.display_login}."
    redirect_to stafftools_user_copilot_settings_path(this_user, notifications: result)
  end

  sig { void }
  def update_quotas # rubocop:todo GitHub/UseRestfulActions
    if this_user.feature_flag_enabled?(:copilot_premium_quota_reset, default: false)
      update_quotas_v2
    else
      update_quotas_v1
    end
  end

  sig { void }
  def update_quotas_v1 # rubocop:todo GitHub/UseRestfulActions
    redirect_to stafftools_user_copilot_settings_path(this_user) and return unless this_user.is_a?(User)

    luser = Copilot::LimitedUser.subscribed.find_by(user: this_user)

    unless luser.present?
      flash[:error] = "User is not a Copilot Limited User"
      redirect_to stafftools_user_copilot_settings_path(this_user) and return
    end

    limited_user = T.must(luser)

    GitHub.logger.with_named_tags(
      "gh.staff.id": current_user.id,
      "gh.user.id": this_user.id,
      "gh.copilot.limited_user.id": limited_user.id,
      "code.namespace": self.class.name,
      "code.function": __method__,
    ) do
      if params[:quotas].present?
        GitHub.logger.info("Updating quotas")

        params[:quotas].each do |quota, value|
          current_value = limited_user.feature_quota_remaining(feature: quota)
          new_value     = value.to_i

          GitHub.logger.with_named_tags(
            "gh.copilot.quota.feature": quota,
            "gh.copilot.quota.old_value": current_value,
            "gh.copilot.quota.new_value": value,
          ) do
            if current_value == new_value
              GitHub.logger.info("Skipping same quota update")
              next
            end

            GitHub.logger.info("Setting quota")

            result = limited_user.set_quota_remaining(feature: quota, quota: value.to_i)

            if result.ok?
              GitHub.logger.info("Successfully updated quota")
              Copilot::Instrumenter.instrument_free_quota_changed_by_staff(
                this_user,
                current_user,
                quota,
                current_value,
                new_value,
              )
            else
              GitHub.logger.error(
                "Failed to update quota",
                "gh.copilot.quota.error": result.error,
              )
              flash[:error] = "Cannot update quota for #{quota} - #{result.error}"
              break
            end
          end
        end

        flash[:notice] = "Copilot quotas updated for #{this_user.display_login}."
      else
        flash[:error] = "No quotas to update"
      end

      redirect_to stafftools_user_copilot_settings_path(this_user)
    end
  end

  sig { void }
  def update_quotas_v2 # rubocop:todo GitHub/UseRestfulActions
    redirect_to stafftools_user_copilot_settings_path(this_user) and return unless this_user.is_a?(User)

    copilot_user = Copilot::User.new(this_user)
    limited = copilot_user.has_limited_access?
    consumptive = copilot_user.consumptive_user?

    luser = Copilot::LimitedUser.subscribed.find_by(user: this_user)

    if consumptive == false && limited == true && !luser.present?
      flash[:error] = "User is not a Copilot Limited User"
      redirect_to stafftools_user_copilot_settings_path(this_user) and return
    end

    if consumptive == false && limited == false
      flash[:error] = "User is not a Copilot Limited User or Copilot Consumptive User"
      redirect_to stafftools_user_copilot_settings_path(this_user) and return
    end

    error_message = T.let(nil, T.nilable(String))
    success = T.let(nil, T.nilable(T::Boolean))

    GitHub.logger.with_named_tags(
      "gh.staff.id": current_user.id,
      "gh.user.id": this_user.id,
      "gh.copilot.limited_user.id": luser&.id,
      "gh.copilot.is_consumptive_user": consumptive,
      "gh.copilot.is_limited_user": limited,
      "code.namespace": self.class.name,
      "code.function": __method__,
    ) do
      if params[:quotas].present?
        GitHub.logger.info("Updating quotas")

        params[:quotas].each do |quota, value|
          current_value = copilot_user.quota_feature_entitlement(feature: quota)
          new_value     = value.to_i

          GitHub.logger.with_named_tags(
            "gh.copilot.quota.feature": quota,
            "gh.copilot.quota.old_value": current_value,
            "gh.copilot.quota.new_value": value,
          ) do
            if current_value == new_value
              GitHub.logger.info("Skipping same quota update")
              next
            end

            GitHub.logger.info("Setting quota")

            result = copilot_user.set_quota_feature_entitlement(feature: quota, quota: value.to_f)

            if result.ok?
              GitHub.logger.info("Successfully updated quota")
              Copilot::Instrumenter.instrument_free_quota_changed_by_staff(
                this_user,
                current_user,
                quota,
                current_value.to_i,
                new_value,
              )
              success = true
            else
              GitHub.logger.error(
                "Failed to update quota",
                "gh.copilot.quota.error": result.error,
              )
              error_message = "Cannot update quota for #{quota} - #{result.error}"
              success = false
              break
            end
          end
        end

        if error_message.present?
          flash[:error] = error_message
        elsif success == true
          flash[:notice] = "Copilot quotas updated for #{this_user.display_login}. This change will take a few minutes to process."
        else
          # should never get to this point, but just in case lets render a warning
          flash[:warning] = "Something may have gone wrong and Copilot quotas may not have been reset"
        end
      else
        flash[:error] = "No quotas to update"
      end

      redirect_to stafftools_user_copilot_settings_path(this_user)
    end
  end

  sig { void }
  def refresh_quotas_cache # rubocop:todo GitHub/UseRestfulActions
    redirect_to stafftools_user_copilot_settings_path(this_user) and return unless this_user.is_a?(User)
    if current_user.feature_flag_enabled?(:copilot_quota_refresh_cache_stafftools, default: false)
      GitHub.logger.info(
        "Refreshing quota cache in Stafftools",
        "gh.org.id" => this_user.id,
        "gh.user.id" => current_user.id,
      )
      Copilot::Instrumenter.instrument_copilot_license_or_billable_customer_change(Copilot::Public::User.new(this_user))
      flash[:info] = "Refreshed Copilot limiter quota cache"
    end
    redirect_to stafftools_user_copilot_settings_path(this_user)
  end

  sig { void }
  def update_plan # rubocop:todo GitHub/UseRestfulActions
    GitHub.dogstats.increment "copilot.stafftools.org.update_plan"
    GitHub.logger.info(
      "Updating Copilot Plan in Organization Stafftools",
      "gh.org.id" => this_user.id,
      "gh.user.id" => current_user.id,
      "gh.copilot_plan" => params[:plan],
    )

    if params[:schedule]
      if params[:plan] == "business"
        copilot_organization.schedule_copilot_plan_downgrade!(::User.staff_user)
        flash[:info] = "Scheduled downgrade to Copilot Business on #{this_user.next_metered_billing_cycle_starts_at}"
      else
        flash[:error] = "Cannot downgrade to a plan other than Copilot Business"
      end
    elsif params[:plan] == "business"
      # if there's a pending downgrade date, clear it because we're downgrading immediately
      copilot_organization.cancel_copilot_plan_downgrade!
      copilot_organization.copilot_plan_business!
      ::Copilot::Instrumenter.instrument_copilot_plan_changed(::User.staff_user, this_user, "enterprise", "business")

      flash[:info] = "Downgraded organization to Copilot Business"
    elsif params[:plan] == "enterprise"
      copilot_organization.copilot_plan_enterprise! # sends email by default
      copilot_organization.copilot_for_dotcom_enabled!

      ::Copilot::Instrumenter.instrument_copilot_plan_changed(::User.staff_user, this_user, "business", "enterprise")

      flash[:info] = "Upgraded organization to Copilot Enterprise"
    else
      flash[:error] = "Could not update to invalid Copilot plan type"
    end

    redirect_to stafftools_user_copilot_settings_path(this_user)
  end

  sig { void }
  def refresh_cache  # rubocop:todo GitHub/UseRestfulActions
    copilot_user = Copilot::User.new(this_user)
    copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
    flash[:info] = "Refreshed Copilot settings cache"
    redirect_to stafftools_user_copilot_settings_path(this_user)
  end

  sig { void }
  def cancel_and_refund # rubocop:todo GitHub/UseRestfulActions
    subscription_type = params[:subscription_type]&.to_sym

    unless [:pro, :pro_plus].include?(subscription_type)
      set_alert_and_redirect("Invalid subscription type specified.")
      return
    end

    copilot_user = Copilot::User.new(this_user)

    # Validate Pro Plus subscription specifically
    if subscription_type == :pro_plus && !copilot_user.has_pro_plus_subscription?
      set_alert_and_redirect("User does not have an active Copilot Pro+ subscription.")
      return
    end

    subscription_item = get_active_subscription_item(copilot_user)
    return unless subscription_item

    type_display = subscription_type.to_s.tr("_", " ").titleize

    GitHub.logger.info(
      "Canceling Copilot #{type_display} subscription item from stafftools",
      "gh.user.login" => this_user,
      "gh.actor.login" => current_user,
      "gh.billing.subscription_item.id" => subscription_item.id
    )

    begin
      # Use the Billing API's cancel_and_refund method on the product identifier
      result = Billing::Public::SubscriptionItem.cancel_and_refund(
        product: subscription_item.product_identifier,
        account: this_user,
        allow_cancelling_iap: true
      )

      if result.ok?
        copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
        flash[:notice] = "Copilot #{type_display} subscription canceled and refund initiated"
      else
        error_message = result.error || "Unknown error occurred"
        flash[:alert] = "There was an error canceling the Copilot #{type_display} subscription: #{error_message}"
      end

    rescue StandardError => e
      GitHub.logger.error(
        "Failed to cancel and refund Copilot #{type_display} subscription",
        :error => e.message,
        "gh.user.login" => this_user,
        "gh.actor.login" => current_user,
        "gh.billing.subscription_item.id" => subscription_item.id
      )
      flash[:alert] = "There was an error canceling the Copilot #{type_display} subscription. Please try again later."
    end

    # Force a redirect to ensure page refreshes with updated data
    redirect_to stafftools_user_copilot_settings_path(this_user)
  end

  sig { void }
  def unsubscribe_limited_user # rubocop:todo GitHub/UseRestfulActions
    copilot_user = Copilot::User.new(this_user)

    GitHub.logger.info(
      "Canceling subscription item from stafftools",
      "gh.user.login" => this_user,
      "gh.actor.login" => current_user,
    )
    begin
      limited_user = Copilot::LimitedUser.find_by(user: this_user)
      limited_user&.destroy
      Copilot::Instrumenter.instrument_free_user_unsubscribed_by_staff(
        this_user,
        current_user,
      )
    rescue StandardError => e
      GitHub.logger.error("Failed to cancel subscription: ", error: e.message)
      flash[:alert] = "There was an error canceling the Copilot Free subscription. Please try again later."
      redirect_to stafftools_user_copilot_settings_path(this_user) and return
    end

    flash[:notice] = "Copilot Free subscription canceled"
    redirect_to stafftools_user_copilot_settings_path(this_user)
  end

  sig { void }
  def update_seat_management_setting # rubocop:todo GitHub/UseRestfulActions
    redirect_to stafftools_user_copilot_settings_path(this_user) and return unless this_user.is_a?(Organization) && params[:copilot_seat_management].present?

    old_seat_management_setting = copilot_organization.seat_management_setting
    keep_assignments = false
    case params[:copilot_seat_management]
    when "disabled"
      copilot_organization.seat_management_disable!
    when "enabled_for_all"
      copilot_organization.seat_management_allow_all!
    when "enabled_for_selected"
      copilot_organization.seat_management_selected_teams_and_users!(keep_assignments: false)
    when "enabled_for_selected_keep_assignments"
      keep_assignments = true
      copilot_organization.seat_management_selected_teams_and_users!(keep_assignments: true)
    end

    new_seat_management_setting = Copilot::Organization.new(copilot_organization.organization_object).seat_management_setting

    Copilot::Instrumenter.instrument_copilot_for_business_seat_management_changed(
      ::User.staff_user,
      copilot_organization.organization_object,
      old_seat_management_setting,
      new_seat_management_setting,
      keep_assignments: keep_assignments
    )

    GitHub.logger.info(
      "Updating seat management setting in Stafftools",
      "gh.org.id" => this_user.id,
      "gh.user.id" => current_user.id,
    )
    flash[:info] = "Updated Copilot seat management setting for #{this_user.display_login}."
    redirect_to stafftools_user_copilot_settings_path(this_user)
  end

  sig { void }
  def update_complimentary_user_type # rubocop:todo GitHub/UseRestfulActions
    free_user = Copilot::FreeUser.find_by(user: this_user)
    previous_type = free_user&.free_user_type
    new_type = params[:copilot_seat_management]

    unless free_user && new_type.present?
      flash[:error] = "Missing user or complimentary user type."
      redirect_to stafftools_user_copilot_settings_path(this_user) and return
    end

    if Copilot::FreeUser::FREE_USER_TYPES.map(&:name).include?(new_type)
      T.must(free_user).update!(free_user_type: new_type)
      copilot_user = Copilot::User.new(this_user)
      copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
      GitHub.logger.info(
        "Updating complimentary access type in Stafftools",
        "gh.staff_user.id" => current_user.id,
        "gh.user.id" => this_user.id,
        "gh.copilot.free_user_type" => new_type,
        "gh.copilot.free_user.previous_type" => previous_type,
      )
      flash[:notice] = "Complimentary user type updated to #{new_type}."
    else
      flash[:error] = "Invalid complimentary user type."
    end

    redirect_to stafftools_user_copilot_settings_path(this_user)
  end

  private

  sig { void }
  def entity_required
    render_404 unless this_user
  end

  sig { returns(Copilot::Organization) }
  memoize def copilot_organization
    Copilot::Organization.new(this_user)
  end

  sig do
    params(
      type: Copilot::FreeUser::Type,
      cancel_subscription: T::Boolean,
      last_checked_date: Date,
      complimentary_access_reason_explanation: String,
    ).void
  end
  def create_free_user(type, cancel_subscription: false, last_checked_date: Date.today, complimentary_access_reason_explanation: "no_explanation_required")
    copilot_user = Copilot::User.new(this_user)
    free_user_type = type.name

    if cancel_subscription && (copilot_user.has_active_subscription? || copilot_user.has_trial_subscription? || copilot_user.has_limited_access?)
      subscription_item = Billing::SubscriptionItem.find_by(id: copilot_user.copilot_active_subscription_item&.id)

      if subscription_item.present?
        GitHub.logger.info(
          "Canceling subscription item for free access",
          "gh.user.login" => this_user,
          "gh.actor.login" => current_user,
          "gh.copilot.free_user.free_user_type" => free_user_type,
          "gh.copilot.free_user.last_checked_date" => last_checked_date,
          "gh.copilot.free_user.access_explanation" => complimentary_access_reason_explanation,
        )

        result = subscription_item.cancel!(actor: current_user, force: true)
        log_msg = result.result.success ? "Canceled Subscription" : "Failed to cancel subscription"

        GitHub.logger.info(
          log_msg,
          "gh.user.login" => this_user,
          "gh.actor.login" => current_user,
          "gh.copilot.free_user.free_user_type" => free_user_type,
          "gh.copilot.free_user.last_checked_date" => last_checked_date,
          "gh.copilot.free_user.access_explanation" => complimentary_access_reason_explanation,
        )
      end
    end

    Copilot::FreeUser.create!(
      user: this_user,
      free_user_type: free_user_type,
      last_checked_date: last_checked_date,
    )

    GitHub.logger.info(
      "Granting free copilot access",
      "gh.user.login" => this_user,
      "gh.actor.login" => current_user,
      "gh.copilot.free_user.free_user_type" => free_user_type,
      "gh.copilot.free_user.last_checked_date" => last_checked_date,
      "gh.copilot.free_user.access_explanation" => complimentary_access_reason_explanation,
    )

    Copilot::Instrumenter.instrument_free_access_granted(
      this_user,
      current_user,
      free_user_type,
      last_checked_date,
      complimentary_access_reason_explanation,
    )
  end

  sig { params(copilot_user: Copilot::User).returns(T.nilable(::Billing::Public::SubscriptionItem)) }
  def get_active_subscription_item(copilot_user)
    subscription_item = copilot_user.copilot_active_subscription_item
    unless subscription_item
      set_alert_and_redirect("User does not have an active Copilot subscription.")
      return nil
    end

    subscription_item
  end

  sig { params(message: String).void }
  def set_alert_and_redirect(message)
    flash[:alert] = message
    redirect_to stafftools_user_copilot_settings_path(this_user)
  end
end
