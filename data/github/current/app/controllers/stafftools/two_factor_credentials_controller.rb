# typed: true
# frozen_string_literal: true

class Stafftools::TwoFactorCredentialsController < StafftoolsController

  before_action :ensure_user_exists
  before_action :ensure_two_factor_enabled
  before_action :ensure_two_factor_configured
  before_action :ensure_sms_configured, only: [:send_test_sms]

  layout "layouts/stafftools/user/security"

  # Send the user a test SMS message to the number they have configured for 2FA
  # The message includes a reference to GitHub Support, since it will be
  # sent manually from stafftools.
  def send_test_sms # rubocop:todo GitHub/UseRestfulActions
    code = "%06X" % rand(16**5)  # get a random six-place hex number
    message = "This is GitHub Support sending a test message: #{code}"
    backup = params[:backup] ? true : false
    begin
      provider = this_user.two_factor_sms_provider(for_backup_number: backup)
      instrument("staff.send_2fa_test_message", user: this_user, code: code, sms_number: sms_number, provider: provider)
      GitHub::SMS.send_message(sms_number, message, this_user,
        provider: provider,
        reason: :stafftools_test
      )
      flash[:notice] = "Message sent#{' to backup' if backup}! (using code #{code})"
    rescue GitHub::SMS::Error
      flash[:error] = "Message failed to send."
    end
    redirect_to :back
  end

  def check_otp # rubocop:todo GitHub/UseRestfulActions
    otp_code = params[:otp_code]
    timestamp, type = this_user.two_factor_otp_valid_timestamp_for_stafftools otp_code

    if timestamp
      relativity = (timestamp > Time.now) ? "will be" : "was"
      flash[:notice] = "#{otp_code} #{relativity} valid for #{this_user} at #{timestamp.utc} for their #{type == :sms ? 'SMS number' : 'authenticator app'}"
    else
      flash[:error] = "#{otp_code} was not valid for #{this_user} within 24 hours of now"
    end

    instrument("staff.check_otp_code", user: this_user, otp_code: otp_code, valid: !!timestamp)

    redirect_to :back
  end

  def change_sms_provider # rubocop:todo GitHub/UseRestfulActions
    provider = GitHub::SMS.get_provider(params[:provider]).provider_name.to_s

    success = T.let(false, T::Boolean)
    User.transaction do
      all_sms_registrations_saved = this_user.sms_registrations.all? do |reg|
        reg.sms_provider = provider
        reg.save
      end
      raise ActiveRecord::Rollback unless all_sms_registrations_saved
      success = true
    end

    if success
      flash[:notice] = "SMS provider set to #{provider.humanize}"
    else
      flash[:error] = "Failed to set SMS provider"
    end
    redirect_to :back
  end

  def approve_2fa_removal_request # rubocop:todo GitHub/UseRestfulActions
    id = params[:request_id]
    emails = params[:emails]
    reason = params[:two_factor_recovery_approve_reason]

    return render_404 unless recovery_request = this_user.two_factor_recovery_requests.find_by_id(id)

    recovery_request.approve(current_user, emails)

    instrument("two_factor_account_recovery.staff_approve", user: this_user, reason: reason)

    GlobalInstrumenter.instrument("two_factor_account_recovery.updated",
      action_type: :STAFF_APPROVED,
      user: this_user,
      evidence_type: recovery_request.hydro_evidence_type,
    )

    GitHub.dogstats.increment(
      "two_factor_account_recovery.completed",
      tags: ["status:approved", "reason:manual_approval",
        "gh_mobile_two_factor_available:#{this_user.gh_mobile_auth_available?}",
        "u2f_available:#{this_user.u2f_registrations.any?}",
        "synced_u2f_available:#{this_user.u2f_registrations.where(backup_state: true).any?}"]
    )

    redirect_to :back
  end

  def decline_2fa_removal_request # rubocop:todo GitHub/UseRestfulActions
    id = params[:request_id]
    reason = params[:two_factor_recovery_decline_reason]

    return render_404 unless recovery_request = this_user.two_factor_recovery_requests.find_by_id(id)

    recovery_request.update!(reviewer: current_user, declined_at: Time.now)

    AccountRecoveryMailer.request_declined_by_staff(this_user).deliver_later

    instrument("two_factor_account_recovery.staff_decline", user: this_user, reason: reason)

    GlobalInstrumenter.instrument("two_factor_account_recovery.updated",
      action_type: :STAFF_DECLINED,
      user: this_user,
      evidence_type: recovery_request.hydro_evidence_type,
    )

    GitHub.dogstats.increment(
      "two_factor_account_recovery.completed",
      tags: ["status:declined", "reason:#{reason}", "gh_mobile_two_factor_available:#{this_user.gh_mobile_auth_available?}"]
    )

    redirect_to :back
  end

  def destroy
    reason = params[:reason]

    if reason.blank?
      flash[:error] = "You must provide a reason for the log"
    elsif !this_user.two_factor_auth_can_be_disabled_by_staff?
      flash[:error] = <<-STR
        Cannot disable two-factor authentication. @#{this_user} is an outside collaborator
        within at least one organization or enterprise account that requires
        2FA to be enabled.
      STR
    else
      this_user.two_factor_credential.destroy
      instrument("staff.two_factor_disable", user: this_user, note: reason)
      flash[:notice] = "Two-factor authentication disabled for @#{this_user}"
    end

    redirect_to :back
  end

  private

  def ensure_two_factor_enabled
    render_404 unless GitHub.auth.two_factor_authentication_enabled?
  end

  def ensure_two_factor_configured
    render_404 unless this_user.two_factor_authentication_enabled?
  end

  def ensure_sms_configured
    render_404 unless (this_user.two_factor_sms_enabled? || this_user.two_factor_sms_fallback_enabled?) && sms_number
  end

  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def sms_number # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @sms_number ||= begin
      if params[:backup]
        this_user.two_factor_backup_sms_number if this_user.two_factor_sms_fallback_enabled?
      else
        if this_user.two_factor_sms_enabled?
          this_user.two_factor_sms_number
        elsif this_user.two_factor_sms_fallback_enabled?
          this_user.two_factor_backup_sms_number
        end
      end
    end
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator
end
