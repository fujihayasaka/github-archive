# typed: strict
# frozen_string_literal: true

class Stafftools::CopilotSettingsController < StafftoolsController
  include CopilotBlockHelper
  extend T::Sig
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
    only: [:show]

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
      }
    end
  end

  sig { void }
  def create
    complimentary_access_reason = params[:complimentary_access_reason]

    if complimentary_access_reason.blank?
      flash[:error] = "Please select a reason for complimentary access"
      redirect_to stafftools_user_copilot_settings_path(this_user.display_login) and return
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
      redirect_to stafftools_user_copilot_settings_path(this_user.display_login) and return
    when "complimentary_access"
      complimentary_access_duration = params[:complimentary_access_duration]

      if complimentary_access_duration.blank?
        flash[:error] = "Please select a duration for complimentary access"
        redirect_to stafftools_user_copilot_settings_path(this_user.display_login) and return
      end

      complimentary_access_reason_explanation = params[:complimentary_access_reason_explanation]

      if complimentary_access_reason_explanation.blank?
        flash[:error] = "Please enter an explanation for complimentary access"
        redirect_to stafftools_user_copilot_settings_path(this_user.display_login) and return
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
          redirect_to stafftools_user_copilot_settings_path(this_user.display_login) and return
        end

        create_free_user(
          Copilot::FreeUser::COMPLIMENTARY_ACCESS,
          cancel_subscription: true,
          last_checked_date: date,
          complimentary_access_reason_explanation: complimentary_access_reason_explanation,
        )
      else
        flash[:error] = "Invalid complimentary access duration"
        redirect_to stafftools_user_copilot_settings_path(this_user.display_login) and return
      end

      flash[:notice] = "Complimentary User created"
      redirect_to stafftools_user_copilot_settings_path(this_user.display_login) and return
    else
      flash[:error] = "Unknown complimentary access reason"
      redirect_to stafftools_user_copilot_settings_path(this_user.display_login) and return
    end
  end

  sig { void }
  def destroy
    remove_access_reason_explanation = params[:remove_access_reason_explanation]

    if remove_access_reason_explanation.blank?
      flash[:error] = "Please enter a reason for removing complimentary access"
      redirect_to stafftools_user_copilot_settings_path(this_user.display_login) and return
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
    redirect_to stafftools_user_copilot_settings_path(this_user.display_login) and return
  end

  sig { void }
  def generate_csv # rubocop:todo GitHub/UseRestfulActions
    copilot_organization = ::Copilot::Organization.new(this_user)
    GitHub.dogstats.increment "copilot.stafftools.org.generate_csv"
    GitHub.logger.info("Generating CSV in Organization Stafftools", "gh.org.id" => copilot_organization.id, "gh.user.id" => current_user.id)
    send_data copilot_organization.to_csv, filename: "#{this_user.display_login.parameterize}-seat-usage-#{Time.current.to_i}.csv"
  end

  sig { void }
  def auth_and_capture  # rubocop:todo GitHub/UseRestfulActions
    copilot_entity = if this_user.organization?
      Copilot::Organization.new(this_user)
    else
      Copilot::User.new(this_user)
    end

    copilot_entity.perform_auth_and_capture!(skip_account_age_check: true, skip_previous_authorizations_check: true, audit_log_reason: "stafftools")

    GitHub.logger.info(
      "Copilot auth and capture triggered by stafftools",
      "gh.user.login" => this_user,
      "gh.actor.login" => current_user,
    )
    flash[:notice] = "Authorization check triggered. You may need to refresh the page"

    redirect_to stafftools_user_copilot_settings_path(this_user.display_login)
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

    redirect_to stafftools_user_copilot_settings_path(this_user.display_login)
  end

  sig { void }
  def warn_via_sire # rubocop:todo GitHub/UseRestfulActions
    copilot_user = Copilot::User.new(this_user)
    reason = params[:warn_reason].to_s

    if copilot_user.has_been_warned?
      flash[:error] = "User already has been notified via SIRE"
      redirect_to stafftools_user_copilot_settings_path(this_user.display_login)
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
      redirect_to stafftools_user_copilot_settings_path(this_user.display_login)
    end
  end

  sig { void }
  def toggle_email_notifications # rubocop:todo GitHub/UseRestfulActions
    redirect_to stafftools_user_copilot_settings_path(this_user.display_login) and return unless this_user.is_a?(Organization)

    if Copilot.copilot_communication_opt_out?(this_user)
      this_user.disable_feature(:copilot_communication_opt_out)
    else
      this_user.enable_feature(:copilot_communication_opt_out)
    end

    result = this_user.feature_enabled?(:copilot_communication_opt_out) ? "disabled" : "enabled"

    GitHub.logger.info(
      "Copilot email notifications #{result} via stafftools",
      "gh.user.login" => this_user,
      "gh.actor.login" => current_user,
    )

    flash[:notice] = "Copilot email notifications #{result} for #{this_user.display_login}."
    redirect_to stafftools_user_copilot_settings_path(this_user.display_login)
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
      copilot_organization.copilot_for_dotcom_disabled!
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

    if cancel_subscription && (copilot_user.has_active_subscription? || copilot_user.has_trial_subscription?)
      subscription_item = Billing::SubscriptionItem.find(T.must(copilot_user.copilot_active_subscription_item).id)

      GitHub.logger.info(
        "Canceling subscription item for free access",
        "gh.user.login" => this_user,
        "gh.actor.login" => current_user,
        "gh.copilot.free_user.free_user_type" => free_user_type,
        "gh.copilot.free_user.last_checked_date" => last_checked_date,
        "gh.copilot.free_user.access_explanation" => complimentary_access_reason_explanation,
      )

      result = subscription_item.cancel!(actor: current_user, force: true)
      log_msg = result.success ? "Canceled Subscription" : "Failed to cancel subscription",

      GitHub.logger.info(
        log_msg,
        "gh.user.login" => this_user,
        "gh.actor.login" => current_user,
        "gh.copilot.free_user.free_user_type" => free_user_type,
        "gh.copilot.free_user.last_checked_date" => last_checked_date,
        "gh.copilot.free_user.access_explanation" => complimentary_access_reason_explanation,
      )
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
end
