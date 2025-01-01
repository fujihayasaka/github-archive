# typed: strict
# frozen_string_literal: true

module Business::LicenseAttributer::InvitesDependency
  extend T::Sig
  extend T::Helpers

  extend ActiveSupport::Concern

  include GitHub::Memoizer

  requires_ancestor { Business::LicenseAttributer }

  # Invitations to the business for users not licensed elsewhere
  sig { returns({ user_ids: T::Set[Integer], emails: T::Set[String] }) }
  def invitations
    { user_ids: user_ids_invitations, emails: emails_invitations }
  end

  # Returns a hash of users to orgs invitations
  # Used for invitation lookup, not license calculations since this will include members who are licensed elsewhere.
  sig { returns(T::Hash[T.any(Integer, String), T::Array[String]]) }
  memoize def pending_member_org_invites_hash
    business.pending_member_invitations.includes(:organization).each_with_object({}) do |invite, invites_orgs|
      key = invite.invitee_id.nil? ? invite.email : invite.invitee_id
      invites_orgs[key] = []
      invites_orgs[key] << invite.organization.display_login
    end
  end

  # Subset of user_ids, limited to those which are invitations only.
  # Does not show users that already have a license elsewhere.
  sig { returns(T::Set[Integer]) }
  memoize def user_ids_invitations
    GitHub.tracer.in_span("Business::LicenseAttributer::InvitesDependency#user_ids_invitations", kind: :internal) do
      if business.enterprise_managed_user_enabled?
        # Invitations are not enabled for EMUs, they just get added to organizations
        Set.new
      else
        (
          non_expired_pending_member_invitations_invitee_ids +
          pending_collaborator_invitation_user_ids
        ).to_set - user_ids_with_access
      end
    end
  end

  # Subset of emails, limited to those which are invitations only.
  # Does not include emails that are licensed elsewhere.
  sig { returns(T::Set[String]) }
  memoize def emails_invitations
    if business.enterprise_managed_user_enabled?
      # Invitations are not enabled for EMUs, they just get added to organizations
      Set.new
    else
      (
        non_expired_pending_member_invitations_emails +
        pending_collaborator_invitation_emails
      ).to_set -
      emails_with_access -
      # Exclude emails that are associated with members of the business. This prevents existing members
      # that are invited via email to another organization under the business from being double counted.
      verified_business_user_emails.map { |email_record| email_record[:email].downcase }
    end
  end

  sig { returns(T::Array[Integer]) }
  memoize def pending_collaborator_invitation_user_ids
    pending_collaborator_invitation_user_ids_and_emails.map(&:first).compact
  end

  sig { returns(T::Array[String]) }
  memoize def pending_collaborator_invitation_emails
    pending_collaborator_invitation_user_ids_and_emails.map(&:last).compact
  end

  sig { returns(T::Array[[Integer, String]]) }
  memoize def pending_collaborator_invitation_user_ids_and_emails
    business.pending_collaborator_invitations(
      repository_visibility: :private,
      include_forks: false
    ).excluding_expired
      .pluck(:invitee_id, :email)
  end

  # Pending administrator invitations for the business. These do not consume a license.
  sig { returns(T::Array[{ invitee_id: Integer, email: String }]) }
  memoize def business_pending_admin_invites
    business.pending_admin_invitations.pluck(:invitee_id, :normalized_email).map do |invitee_id, email|
      { invitee_id: invitee_id, email: email }
    end
  end

  sig { returns(T::Array[String]) }
  def business_pending_admin_invites_emails
    business_pending_admin_invites.filter_map { |invite| invite[:email].downcase if invite[:email] }.uniq
  end

  sig { returns(T::Array[Integer]) }
  def business_pending_admin_invites_user_ids
    business_pending_admin_invites.filter_map { |invite| invite[:invitee_id] }.uniq
  end

  # Returns users that have pending invitations to collaborate on a public repository.
  # These invitations do not consume a license.
  sig { returns(T::Array[[Integer, String]]) }
  memoize def public_collaborator_invitations
    business.pending_collaborator_invitations(
      repository_visibility: :public,
      include_forks: false
    ).excluding_expired
      .pluck(:invitee_id, :email)
  end

  sig { returns(T::Array[Integer]) }
  def public_collaborator_invitations_user_ids
    public_collaborator_invitations.map(&:first).compact
  end

  sig { returns(T::Array[String]) }
  def public_collaborator_invitations_emails
    public_collaborator_invitations.map(&:last).compact.map(&:downcase)
  end

  # Returns an array of hashes with the following keys: invitee_id, email
  sig { returns(T::Array[{ invitee_id: Integer, email: String }]) }
  memoize def non_expired_pending_member_invitations
    business.pending_member_invitations.excluding_expired.pluck(:invitee_id, :normalized_email).map do |invitee_id, email|
      { invitee_id: invitee_id, email: email }
    end
  end

  # Returns an array of non-expired invitations to user_ids.
  sig { returns(T::Array[Integer]) }
  def non_expired_pending_member_invitations_invitee_ids
    non_expired_pending_member_invitations.filter_map { |invite| invite[:invitee_id] }.uniq
  end

  # Returns an array of non-expired invitations to email addresses.
  sig { returns(T::Array[String]) }
  def non_expired_pending_member_invitations_emails
    non_expired_pending_member_invitations.filter_map { |invite| invite[:email].downcase if invite[:email] }.uniq
  end
end
