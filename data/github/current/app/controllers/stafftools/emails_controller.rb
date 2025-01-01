# typed: true
# frozen_string_literal: true

class Stafftools::EmailsController < StafftoolsController
  extend T::Helpers

  before_action :ensure_user_exists
  before_action :ensure_billing_enabled, only: [:destroy_billing_external_email]
  before_action :dotcom_required, only: [:duplicates]
  before_action \
    :ensure_email_verification_enabled,
    only: [
      :disable_mandatory_email_verification,
      :restore_mandatory_email_verification,
    ]

  layout :new_nav_layout
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  private def new_nav_layout
    case this_user.site_admin_context
    when "organization"
      "layouts/stafftools/organization/overview"
    when "user"
      "layouts/stafftools/user/overview"
    end
  end

  def index
    # ensure email verification actions redirect to staff land
    store_location
    render "stafftools/emails/index"
  end

  def duplicates # rubocop:todo GitHub/UseRestfulActions
    @emails = GitHub::SpamChecker.find_obfuscated_duplicate_emails(this_user)
    render "stafftools/emails/duplicates"
  end

  # Adds an email to the user's account
  def create
    email = params[:email]

    if UserEmail.duplicate?(email)
      flash[:error] = "Error adding '#{email}' - email is already in use"
      redirect_to :back
      return
    end

    new_email = this_user.add_email(email, actor: current_user)
    if new_email.valid?
      flash[:notice] = "'#{new_email}' added to #{this_user}"
    else
      flash[:error] = "Error adding '#{new_email}' - #{new_email.errors.full_messages.to_sentence}."
    end
    redirect_to :back
  end

  # Deletes an email from the user's account.
  # For GitHub.com, if this is the last user-added email, an "unlinked"
  # replacement email is added before the email is deleted.
  def destroy
    email = this_user.emails.find(params[:id])
    removing_primary = email.primary_role?

    # This should not be possible, but want to block it at the controller level too just to be safe
    if this_user.is_enterprise_managed? && removing_primary
      flash[:error] = "Cannot remove primary email for EMU"
      redirect_to :back
    end

    message = AppSecurity::EmailHelper.unlink_from_account(this_user, email, actor: current_user)

    if message
      flash[:error] = message
    end

    success_message = "Email '#{email}' removed from #{this_user.login}"
    if removing_primary
      success_message << " and replaced with '#{this_user.primary_user_email}'."
      if this_user.primary_user_email.backup_role?
        success_message << "Note that only the new email can be used for account recovery. You can change this setting by changing your Backup email address at #{GitHub.url}/settings/emails."
      end
    end

    if this_user.primary_user_email.email.ends_with?(".unlinked")
      instrument("staff.disable_notifications", user: this_user)
    end

    flash[:notice] = success_message
    redirect_to :back
  end

  def destroy_billing_external_email # rubocop:todo GitHub/UseRestfulActions
    billing_email = this_user.billing_external_emails.find(params[:id])
    if billing_email.destroy
      flash[:notice] = "Successfully removed from billing recipients."
    else
      flash[:error] = billing_email.errors.full_messages.to_sentence
    end

    redirect_back(fallback_location: stafftools_user_emails_path(this_user))
  end

  def change_email_notifications # rubocop:todo GitHub/UseRestfulActions
    val = params[:value]&.to_s
    GitHub.dogstats.increment("stafftools.change_email_notifications.count", tags: ["enable:#{val}"])

    if val == "true"
      response = GitHub.newsies.get_and_update_settings this_user do |settings|
        settings.participating_settings << "email"
        settings.subscribed_settings << "email"
      end
    else
      response = GitHub.newsies.get_and_update_settings this_user do |settings|
        settings.participating_settings.delete("email")
        settings.subscribed_settings.delete("email")
      end
    end

    if response.success? && change_email_notifications_in_notifyd
      action = val == "true" ? "enable" : "disable"
      instrument("staff.#{action}_notifications", user: this_user)
      flash[:notice] = "Email notifications #{action}d."
    else
      flash[:error] = "Failed to toggle email notifications."
    end

    redirect_to :back
  end

  # Allow staff to mark a user as exempt from mandatory email verification.
  def disable_mandatory_email_verification # rubocop:todo GitHub/UseRestfulActions
    this_user.disable_mandatory_email_verification(actor: current_user)
    flash[:notice] = "Mandatory email verification disabled for @#{this_user}."
    redirect_to :back
  end

  # Allow staff to restore mandatory email verification for a previously exempt user.
  def restore_mandatory_email_verification # rubocop:todo GitHub/UseRestfulActions
    this_user.restore_mandatory_email_verification(actor: current_user)
    flash[:notice] = "Mandatory email verification restored for @#{this_user}."
    redirect_to :back
  end

  # Sets a specific email, for orgs, for user the gravatar email can be updated and first EMU admin email.
  def set_email # rubocop:todo GitHub/UseRestfulActions
    notice = "Updated successfully."
    if this_user.user? && this_user.is_enterprise_managed? && target_params["profile_email"].present?
      notice = this_user.update_first_emu_owner_email target_params["profile_email"]
    else
      this_user.update target_params
    end
    redirect_to :back, notice: notice
  end

  # Fixes an account that has no primary email
  def repair_primary # rubocop:todo GitHub/UseRestfulActions
    if this_user.repair_primary_email
      flash[:notice] = "Primary email set to #{this_user.primary_user_email}"
    else
      flash[:error] = "Error: #{this_user.errors.full_messages.to_sentence}"
    end

    redirect_to :back
  end

  # Fixes an invalid email
  def repair # rubocop:todo GitHub/UseRestfulActions
    if (email = this_user.emails.find params[:id])
      email.update_attribute :email, "#{Time.now.to_i}@invalid.email.com"
      flash[:notice] = "Email has been repaired"
    else
      flash[:error] = "Email not found"
    end
    redirect_to :back
  end

  # Send the user an email verification request email
  #
  # email_id - The UserEmail id of the address to send to.
  def request_verification # rubocop:todo GitHub/UseRestfulActions
    email = this_user.emails.find_by_email(params[:email]) || this_user.emails.unverified.first

    if email && email.request_verification
      flash[:notice] = "Verification Request sent to #{email}"
    elsif email
      flash[:error] = "Unable to send verification email to #{email}"
    else
      flash[:error] = "This user has no unverified emails"
    end

    redirect_to :back
  end

  # Send the user an email unlink request email - only for GitHub.com
  #
  # params[:email] - The email address to initiate unlink for.
  def request_unlink # rubocop:todo GitHub/UseRestfulActions
    email_record = this_user.emails.find_by_email(params[:email])

    flash[:error] = "Unable to find #{params[:email]}." if email_record.nil?
    flash[:error] = "#{email_record} ends in `.unlinked`, delete instead." if email_record&.email&.end_with?(".unlinked")
    flash[:error] = "#{email_record} is flagged as bouncing and cannot be unlinked." if email_record&.bouncing?

    GitHub.dogstats.increment("stafftools.request_email_unlink.count", tags:
      ["verified:#{email_record&.verified?}", "hard_bounce:#{!!email_record&.bouncing?}", "2fa_enabled:#{this_user.two_factor_authentication_enabled?}", "error:#{!!flash[:error]}"])

    if flash[:error]
      redirect_to :back
      return
    end

    # 24 hours instead of the 3 hours set by the EmailUnlink model
    link = EmailUnlink.new(this_user, expires: 24.hours.from_now, email: email_record.email, staff_initiated: true).link
    CriticalAccountLoginMailer.email_unlink_verification(email_record, this_user, link).deliver_later
    this_user.instrument_email_unlink_initiate(actor: current_user, reason: "stafftools", email: email_record.email)

    flash[:notice] = "Email unlink request sent to #{email_record}"
    redirect_to :back
  end

  def disable_marketing_email # rubocop:todo GitHub/UseRestfulActions
    NewsletterPreference.set_to_transactional(user: this_user)
    flash[:notice] = "Disabled marketing email for #{this_user}"
    redirect_to :back
  end

  private

  def ensure_email_verification_enabled
    render_404 unless GitHub.email_verification_enabled?
  end

  def fallback_for_primary_email(user)
    # We let the caller handle the case where this is the user's last email,
    # since several things need to happen (register a placeholder email, disable
    # notifications, etc).
    return nil if user.primary_user_email.last_email?
    # When a user has chosen to allow password resets only with their primary
    # email, we set their backup email to match their primary email. So, we
    # don't want to return their "backup email", since it is the same as the
    # user's primary email.
    if user.has_backup_email? && !user.password_reset_with_primary_email_only?
      return user.backup_user_email
    end
    # If the user doesn't have a backup set, then we search for the next
    # available "notifiable email". Notifiable emails prefer verified emails.
    # However, if no verified emails exist (notice we exclude the user's
    # primary/backup email before doing the search), then it falls over to the
    # first available unverified email.
    user.emails.excluding_ids([user.primary_user_email, user.backup_user_email]).notifiable.first
  end

  def target_params
    params.require(:target).permit(
      :profile_email,
      :billing_email,
      :gravatar_email,
    )
  end

  sig { returns(T::Boolean) }
  def change_email_notifications_in_notifyd
    return true unless Notifyd::Flags.new(this_user).enable_issue_thread_subscriptions?
    settings = GitHub.newsies.settings(this_user)
    return false unless settings.success?

    Notifyd::RoutingSettingsService.save_from_newsies(
      this_user,
      settings.value,
      sections: %i[participating subscribed],
      stat_tags: ["participating_subscribed_stafftools:true"]
    )
  rescue Notifyd::NetworkHelper::APIError => e
    GitHub::Logger.log({
      error: e.message,
      fn: "Stafftools::EmailsController#change_email_notifications_in_notifyd",
      message: "failed to store notification email delivery preferences to notifyd",
    })
    GitHub.dogstats.increment("stafftools.change_email_notifications_in_notifyd.error.count")
    false
  end
end
