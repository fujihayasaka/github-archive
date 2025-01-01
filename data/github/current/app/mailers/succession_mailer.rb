# typed: true
# frozen_string_literal: true

class SuccessionMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  helper_method :help_link

  self.mailer_name = "mailers/succession"

  layout "repository/collab_email_layout"

  def account_successor_invite(invitation)
    @inviter = invitation.inviter
    @invitee = invitation.invitee
    @invitation = invitation

    mail(
        to: user_email(@invitee),
        from: github_noreply,
        reply_to: reply_to(@inviter),
        subject: "#{@inviter} has invited you to be their account successor"
    )
  end

  def account_successor_added(invitation)
    @inviter = invitation.inviter
    @invitee = invitation.invitee
    @invitation = invitation

    mail(
        to: user_email(@inviter),
        from: github_noreply,
        subject: "#{@invitee} has been invited as your account successor"
    )
  end

  def account_successor_removed(invitation)
    @inviter = invitation.inviter
    @invitee = invitation.invitee
    @invitation = invitation

    mail(
        to: user_email(@inviter),
        from: github_noreply,
        subject: "Your account successor has been removed"
    )
  end

  def account_successor_accepted(invitation)
    @inviter = invitation.inviter
    @invitee = invitation.invitee
    @invitation = invitation

    mail(
        to: user_email(@inviter),
        from: github_noreply,
        subject: "Your account succession invitation has been accepted"
    )
  end

  def account_successor_declined(invitation)
    @inviter = invitation.inviter
    @invitee = invitation.invitee
    @invitation = invitation

    mail(
        to: user_email(@inviter),
        from: github_noreply,
        subject: "Your account succession invitation has been declined"
    )
  end

  private

  def reply_to(user)
    user_email(user, allow_private: false) || github_noreply(user)
  end

  def help_link
    SuccessorInvitation.help_link
  end
end
