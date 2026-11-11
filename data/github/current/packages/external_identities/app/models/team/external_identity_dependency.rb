# typed: false
# frozen_string_literal: true

module Team::ExternalIdentityDependency
  # Public: Get a list of user statuses that belong to members of the team.
  #
  # Returns an Array of Users whose external identities match the provided external_members, with their profiles loaded.
  def matched_external_members(external_members)
    external_member_ids = external_members.map(&:id)
    return [] if external_member_ids.empty?

    # Some unit tests skip the provider setup, but in production it will be set and we should scope the query accordingly.
    provider = organization.business&.saml_provider || organization.saml_provider
    external_identities = ExternalIdentity
    external_identities = external_identities.by_provider(provider) if provider
    external_identity_user_ids = external_identities.by_external_id_attribute(external_member_ids).distinct.pluck(:user_id)

    users = members_scope.order("login ASC").where(id: external_identity_user_ids).to_a
    return users if users.empty?

    ActiveRecord::Associations::Preloader.new(records: users, associations: :profile).call
    users
  end
end
