# typed: true
# frozen_string_literal: true

class SuccessorInvitationsController < ApplicationController

  before_action :login_required
  before_action :set_invitation_as_invitee, only: [:show_pending, :accept, :decline]
  before_action :sudo_filter, only: [:create, :revoke, :cancel]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:show_pending]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show_pending],
    optional: true

  def create
    if GitHub.enterprise?
      return render_404
    end

    invitee = User.find_by_login(params[:login])
    if invitee.nil?
      flash[:error] = "Sorry, we couldn't send the invitation at this time."
      return redirect_to settings_account_preferences_path
    end

    begin
      SuccessorInvitation.create!(inviter: current_user, invitee: invitee, target: current_user)
      flash[:notice] = "You have successfully sent the successor invitation to #{invitee.display_login}."
    rescue ActiveRecord::RecordInvalid
      flash[:error] = "Sorry, we couldn't send the invitation at this time."
    ensure
      redirect_to settings_account_preferences_path
    end
  end

  def cancel # rubocop:todo GitHub/UseRestfulActions
    invitation = current_user.successor_invitations.pending.last

    if invitation.nil?
      flash[:error] = "There was a problem canceling this invitation."
      return redirect_to settings_account_preferences_path
    end

    begin
      invitation.cancel(actor: current_user)
      flash[:notice] = "You have canceled the invitation to #{invitation.invitee.display_login} to be your designated successor."
    rescue SuccessorInvitation::AlreadyCanceledError
      flash[:error] = "There was a problem canceling this invitation."
    ensure
      redirect_to settings_account_preferences_path
    end
  end

  def revoke # rubocop:todo GitHub/UseRestfulActions
    invitation = current_user.successor_invitations.accepted.last

    if invitation.nil?
      flash[:error] = "There was a problem revoking this invitation."
      return redirect_to settings_account_preferences_path
    end

    begin
      invitation.revoke(actor: current_user)
      flash[:notice] = "You have revoked the successor invitation to #{invitation.invitee.display_login}."
    rescue SuccessorInvitation::AlreadyCanceledError, SuccessorInvitation::AlreadyAcceptedError
      flash[:error] = "There was a problem revoking this invitation."
    ensure
      redirect_to settings_account_preferences_path
    end
  end

  # shown to invitee
  def show_pending # rubocop:todo GitHub/UseRestfulActions
    if GitHub.enterprise?
      return render_404
    end

    unless @invitation&.acceptable_by?(current_user)
      return render "successor_invitations/not_found", status: 404
    end

    if already_actioned?(@invitation)
      return render "successor_invitations/already_actioned", locals: { invitation: @invitation }
    end

    render "successor_invitations/show_pending", locals: { invitation: @invitation }
  end

  # actioned by invitee
  def accept # rubocop:todo GitHub/UseRestfulActions
    begin
      @invitation.accept(actor: current_user)
      flash[:notice] = "You are now the designated successor for #{inviter.display_login}'s account."
      redirect_to dashboard_path
    rescue SuccessorInvitation::StateChangeError, SuccessorInvitation::ActorPermissionError
      flash[:error] = "There was a problem accepting this invitation."
      redirect_to pending_successor_invitation_path(user_id: inviter.display_login)
    end
  end

  # actioned by invitee
  def decline # rubocop:todo GitHub/UseRestfulActions
    begin
      @invitation.decline(actor: current_user)
      flash[:notice] = "You have declined to become the designated successor for #{inviter.display_login}'s account."
      redirect_to dashboard_path
    rescue SuccessorInvitation::StateChangeError, SuccessorInvitation::ActorPermissionError
      flash[:error] = "There was a problem declining this invitation."
      redirect_to pending_successor_invitation_path(user_id: inviter.display_login)
    end
  end

  def suggestions # rubocop:todo GitHub/UseRestfulActions
    search_term = params[:q]

    headers["Cache-Control"] = "no-cache, no-store"

    suggested_users = User.search(search_term, limit: 10).select do |user|
      current_user.succeedable_by?(user)
    end

    respond_to do |format|
      format.html_fragment do
        render partial: "settings/successor/suggestions", formats: :html, locals: {
            suggestions: suggested_users,
        }
      end
      format.html do
        render partial: "settings/successor/suggestions",
               locals: { formats: :html, suggestions: suggested_users }
      end
    end
  end

  private

  def set_invitation_as_invitee
    if current_user == inviter
      redirect_to settings_account_preferences_path
    end

    @invitation = SuccessorInvitation.where(inviter: inviter, target: inviter).last
  end

  def inviter # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @inviter if defined?(@inviter)
    @inviter = User.find_by_login(params[:user_id])
  end

  def already_actioned?(invite)
    invite.accepted? || invite.declined?
  end

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
