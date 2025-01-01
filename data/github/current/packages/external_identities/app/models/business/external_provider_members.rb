# typed: false
# frozen_string_literal: true

module Business::ExternalProviderMembers
  include GitHub::Memoizer

  # Public: all users associated with the SSO target that have not been
  # linked to an external SSO identity provider.
  #
  # Returns an ActiveRecord::Relation of type User
  def unlinked_external_members
    return User.none unless external_provider_enabled?
    return external_members if linked_external_members.none?
    User.where(id: user_ids_of_unlinked_members).order(:login)
  end

  # Public: all users associated with the SSO target that have not been
  # linked to an external SSO identity provider.
  #
  # Returns an GitHub::BatchedScope::BatchedScopeQuery of type User
  def batched_unlinked_external_members
    return User.none unless external_provider_enabled?
    return external_members if batched_linked_external_members.none?
    User.batched_scope(:id, values: user_ids_of_unlinked_members).order(:login)
  end

  # Public: number of users associated with the SSO target that have not been
  # linked to an external SSO identity provider.
  #
  # Returns an Integer
  memoize def unlinked_external_members_count
    return 0 unless external_provider_enabled?
    return external_members.count if linked_external_members_count < 1
    user_ids_of_unlinked_members.size
  end

  # Public: all users associated with the SSO target that have been
  # linked to an external SSO identity provider.
  #
  # Returns an ActiveRecord::Relation of type User
  def linked_external_members
    return User.none unless external_provider_enabled?
    return User.none if external_provider.external_identities.none?
    User.where(id: user_ids_of_linked_identities).order(:login)
  end

  # Public: all users associated with the SSO target that have been
  # linked to an external SSO identity provider.
  #
  # Returns an GitHub::BatchedScope::BatchedScopeQuery of type User
  def batched_linked_external_members
    return User.none unless external_provider_enabled?
    return User.none if external_provider.external_identities.none?
    User.batched_scope(:id, values: user_ids_of_linked_identities).order(:login)
  end

  # Public: number of users associated with the SSO target that have been
  # linked to an external SSO identity provider.
  #
  # Returns an Integer
  memoize def linked_external_members_count
    return 0 unless external_provider_enabled?
    return 0 if external_provider.external_identities.none?
    user_ids_of_linked_identities.size
  end

  # Public: all external identities associated with the SSO provider
  # that have not been linked to a user.
  #
  # Returns an ActiveRecord::Relation of type ExternalIdentity
  def unlinked_external_identities
    return ExternalIdentity.none unless external_provider_enabled?
    return ExternalIdentity.none if external_provider.external_identities.none?
    ExternalIdentity.where(id: unlinked_external_identity_ids).order(:id)
  end

  # Public: number of external identities associated with the SSO provider
  # that have not been linked to a user.
  #
  # Returns an Integer
  memoize def unlinked_external_identities_count
    return 0 unless external_provider_enabled?
    return 0 if external_provider.external_identities.none?
    unlinked_external_identity_ids.count
  end

  private

  # Internal: the User IDs of all claimed external identities associated with
  # the SSO target via its current SSO identity provider.
  #
  # Returns an Array of Integers
  def user_ids_of_linked_identities
    external_provider.external_identities.user_identities.pluck(:user_id)
  end

  # Internal: the Organization IDs of all claimed external identities associated
  # with the SSO target via its current SSO identity provider.
  #
  # Returns an Array of Integers
  def user_ids_of_linked_org_identities
    external_provider.external_identities.group_identities.pluck(:user_id)
  end

  # Internal: the User IDs of all normal members of this SSO target that have
  # not been linked to the target's current SSO identity provider.
  #
  # Returns an Array of Integers
  def user_ids_of_unlinked_members
    if enterprise_managed_user_enabled?
      [find_first_emu_owner.id]
    else
      external_members.where.not(id: user_ids_of_linked_identities).pluck(:id)
    end
  end

  # Internal: the ExternalIdentity IDs of all external identities associated
  # with the SSO provider that have not been linked to a user.
  #
  # Returns and Array of Integers
  def unlinked_external_identity_ids
    external_provider.external_identities.unlinked.pluck(:id)
  end
end
