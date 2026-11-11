# typed: true
# frozen_string_literal: true

class Businesses::PendingMembersView < Businesses::QueryView
  include BusinessesHelper

  attr_reader :invitations, :business, :organizations, :license, :source, :sort

  EMAIL_INVITATION = "EMAIL"
  USER_INVITATION = "USER"
  BLA_INVITATION = "BLA"

  def initialize(**args)
    super(args)
    @business = args[:business]
    @invitations = args[:invitations]
  end

  def filter_map
    BusinessesHelper::PENDING_MEMBERS_QUERY_FILTERS
  end

  # set up to use `invitations` made of PendingInvitation objects
  def invitations_rollup
    invitations.each_with_object({}) do |invitation, rollup|
      key = rollup.keys.find { |keyed_invite| rollup_invites?(keyed_invite, invitation) }
      key ||= invitation

      rollup[key] ||= { logins: [] }

      rollup[key][:logins] << invitation.original_object.organization.display_login if invitation.org_invite?
    end
  end

  def invitations_total_entries_with_delimiter
    invitations.total_entries > Business::PendingInvitation.max_total_entries ? Business::PendingInvitation::TOTAL_ENTRIES_LABEL : (helpers.number_with_delimiter invitations.total_entries)
  end

  private

  def rollup_invites?(invite, other)
    return false unless invitation_type(invite) == invitation_type(other)

    if invite.org_invite?
      if invitation_type(invite) == EMAIL_INVITATION
        invite.original_object.email == other.original_object.email
      elsif invite.invitee.present? && other.invitee.present?
        invite.invitee.display_login == other.invitee.display_login
      else
        false
      end
    else
      false
    end
  end

  def invitation_type(invitation)
    if invitation.org_invite?
      invitation.original_object.email.present? ? EMAIL_INVITATION : USER_INVITATION
    else
      BLA_INVITATION
    end
  end
end
