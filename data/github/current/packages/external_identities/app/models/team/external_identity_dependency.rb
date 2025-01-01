# typed: false
# frozen_string_literal: true

module Team::ExternalIdentityDependency
  # Public: Get a list of user statuses that belong to members of the team.
  #
  # order_by - an optional Hash for ordering the results; valid keys include:
  #   :field - valid values include "updated_at"
  #   :direction - valid values include "ASC" and "DESC"
  #
  # Returns an Array of UserStatuses.
  def matched_external_members(external_members)
    members = self.members_scope.order("login ASC").includes(:profile)
    identity_provider = ExternalIdentity.identity_provider(self)
    external_member_ids = external_members.map(&:id)

    matched_members = members.map do |member|
      external_identity = mapped_external_identity(member, identity_provider)
      if external_identity
        attributes = external_identity.saml_user_data.map { |d| d.fetch("value") } + external_identity.scim_user_data.map { |d| d.fetch("value") }
        identity_intersection = external_member_ids & attributes.compact
        member unless identity_intersection.empty?
      end
    end

    matched_members.compact
  end

  private

  def mapped_external_identity(member, identity_provider)
    member.external_identities.detect do |exid|
      exid.saml_user_data.fetch(identity_provider) || exid.scim_user_data.fetch(identity_provider)
    end
  end
end
