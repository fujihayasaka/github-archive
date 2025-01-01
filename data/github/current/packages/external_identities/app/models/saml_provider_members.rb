# typed: false
# frozen_string_literal: true

module SamlProviderMembers

  # Public: all users associated with the SAML target that have not been
  # linked to an external SAML identity provider.
  #
  # Returns an ActiveRecord::Relation of type User
  def unlinked_saml_members
    return User.none unless saml_sso_enabled?
    return saml_members if linked_saml_members.none?
    User.where(id: user_ids_of_unlinked_members)
  end

  # Public: all users associated with the SAML target that have been
  # linked to an external SAML identity provider.
  #
  # Returns an ActiveRecord::Relation of type User
  def linked_saml_members
    return User.none unless saml_sso_enabled?
    return User.none if saml_provider.external_identities.none?
    User.where(id: user_ids_of_linked_identities)
  end

  # Public: all orgs associated with the SAML target that have been
  # linked to an external SAML identity provider.
  #
  # Returns an ActiveRecord::Relation of type Organization
  def linked_saml_orgs
    return Organization.none unless saml_sso_enabled?
    return Organization.none if saml_provider.external_identities.none?
    Organization.where(id: user_ids_of_linked_org_identities)
  end

  # Public: all external identities associated with the SAML provider
  # that have not been linked to a user.
  #
  # Returns an ActiveRecord::Relation of type ExternalIdentity
  def unlinked_external_identities
    return User.none unless saml_sso_enabled?
    return User.none if saml_provider.external_identities.none?
    ExternalIdentity.where(id: unlinked_external_identity_ids).order(:id)
  end

  private

  # Internal: the User IDs of all claimed external identities associated with
  # the SAML target via its current SAML identity provider.
  #
  # Returns an Array of Integers
  def user_ids_of_linked_identities
    saml_provider.external_identities.user_identities.pluck(:user_id)
  end

  # Internal: the Organization IDs of all claimed external identities associated
  # with the SAML target via its current SAML identity provider.
  #
  # Returns an Array of Integers
  def user_ids_of_linked_org_identities
    saml_provider.external_identities.group_identities.pluck(:user_id)
  end

  # Internal: the User IDs of all normal members of this SAML target that have
  # not been linked to the target's current SAML identity provider.
  #
  # Returns an Array of Integers
  def user_ids_of_unlinked_members
    saml_members.where.not(id: user_ids_of_linked_identities).pluck(:id)
  end

  # Internal: the ExternalIdentity IDs of all external identities associated
  # with the SAML provider that have not been linked to a user.
  #
  # Returns an Array of Integers
  def unlinked_external_identity_ids
    saml_provider.external_identities.unlinked.pluck(:id)
  end
end
