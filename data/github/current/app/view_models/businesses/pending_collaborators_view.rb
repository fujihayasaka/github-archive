# typed: true
# frozen_string_literal: true

class Businesses::PendingCollaboratorsView < Businesses::QueryView
  include BusinessesHelper

  MAX_REPO_NAMES = 10
  EMAIL_INVITATION = "EMAIL"
  USER_INVITATION = "USER"

  attr_reader :invitations, :business, :sort

  def initialize(**args)
    super(args)
    @business = args[:business]
    @invitations = args[:invitations]
  end

  def repo_count_label(repositories)
    return "Invited to 0 repositories" if repositories.blank?

    repos_for_label = repositories.map(&:name_with_display_owner)[0..MAX_REPO_NAMES]
    omitted_count = repositories.count - repos_for_label.count
    parts = repos_for_label.dup
    parts << helpers.pluralize(omitted_count, "other") if omitted_count > 0

    "Invited to #{parts.to_sentence}"
  end

  def invitations_rollup
    invitations.each_with_object({}) do |invitation, rollup|
      key = rollup.keys.find { |keyed_invite| rollup_invites?(keyed_invite, invitation) }
      key ||= invitation
      rollup[key] ||= { repositories: [] }

      rollup[key][:repositories] << invitation.repository
    end
  end

  def filter_map
    BusinessesHelper::OUTSIDE_COLLABORATORS_INVITATIONS_QUERY_FILTERS
  end

  private

  def rollup_invites?(invite, other)
    return false unless invitation_type(invite) == invitation_type(other)

    if invitation_type(invite) == EMAIL_INVITATION
      invite.email == other.email
    else
      invite.invitee.display_login == other.invitee.display_login
    end
  end

  def invitation_type(invitation)
    invitation.email.present? ? EMAIL_INVITATION : USER_INVITATION
  end
end
