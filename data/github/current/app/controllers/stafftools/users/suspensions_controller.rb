# typed: true
# frozen_string_literal: true

class Stafftools::Users::SuspensionsController < StafftoolsController
  before_action :ensure_user_exists

  # Mark a user as suspended. This prevents the user from being able to login,
  # push, pull, etc.
  #
  # If LDAP sync is enabled with Active Directory, notify the admin that
  # account suspension needs to be managed by LDAP.
  #
  # If the user is a site admin, notify the admin that the account needs to be
  # demoted before being suspended

  def create
    missing_fields = [:reason, :content_formats, :created_at, :source].select { |field| params[field].blank? }
    dsa_submission_not_required = %w[ACCOUNT_TAKEOVER HIDE_FROM_PUBLIC OTHER]

    if !GitHub.show_enterprise_suspend_form? && !dsa_submission_not_required.include?(params[:reason]) && missing_fields.any?
      flash[:error] = "Could not suspend user(s). Please submit responses for the required fields: #{missing_fields.join(", ")}"
      redirect_to stafftools_user_administrative_tasks_path(this_user)
      return
    elsif GitHub.show_enterprise_suspend_form? && params[:reason].nil?
      flash[:error] = "Could not suspend user(s). Please submit a reason for the suspension"
      redirect_to stafftools_user_administrative_tasks_path(this_user)
      return
    end

    reason, content_formats, notes, created_at, source = params.values_at(:reason, :content_formats, :notes, :created_at, :source)

    if this_user.external_account_suspension?
      flash[:error] = "Account suspension is managed by Active Directory. Disable the user from "\
        "your directory."
    else
      if !this_user.suspendable?
        flash[:error] = "Site admins can not be suspended. Remove site admin privileges before "\
          "suspending."
      elsif GitHub.show_enterprise_suspend_form?
        show_suspension_results(this_user.suspend(
          reason,
          actor: current_user,
          send_email: params[:send_email] ? true : false
        ))
      elsif !GitHub.show_enterprise_suspend_form?
        show_suspension_results(this_user.suspend(
          reason,
          actor: current_user,
          send_email: !dsa_submission_not_required.include?(reason),
          dsa_source: dsa_submission_not_required.include?(reason) ? nil : source,
          notes: notes,
          content_formats: content_formats,
          content_creation_date: DateTime.parse(created_at || DateTime.now.to_s),
          items_reported_to_ncmec: params[:items_reported_to_ncmec]
        ))
      else
        flash[:error] = this_user.errors[:base].to_sentence
      end
    end

    redirect_to stafftools_user_administrative_tasks_path(this_user)
  end

  def destroy
    reason = params[:reason]

    if reason.blank?
      reason = "Unsuspended by staff"
    end

    if this_user.external_account_suspension?
      flash[:error] = "Account suspension is managed by Active Directory. Disable the user from "\
        "your directory."
    elsif this_user.sdn_suspended?
      flash[:error] = "This account cannot be unsuspended due to trade restriction."
    else
      reason ||= "Flagged by staff"
      if this_user.unsuspend(reason, actor: current_user)
        flash[:notice] = "#{this_user.login} unsuspended"
      else
        flash[:error] = this_user.errors[:base].to_sentence
      end
    end

    redirect_to stafftools_user_administrative_tasks_path(this_user)
  end

  private

  def show_suspension_results(suspension_results)
    if suspension_results
      billing_part = " and their billing is locked!" if GitHub.billing_enabled?
      flash[:notice] = "#{this_user.login} suspended#{billing_part}"
    else
      flash[:error] = this_user.errors[:base].to_sentence
    end
  end
end
