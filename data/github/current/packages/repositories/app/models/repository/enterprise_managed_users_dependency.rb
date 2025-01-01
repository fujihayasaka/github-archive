# typed: strict
# frozen_string_literal: true

# Adds methods related to repositories owned by enterprise managed users,
# or owned by organizations that belong to enterprise managed businesses.
module Repository::EnterpriseManagedUsersDependency
  extend T::Helpers

  extend ActiveSupport::Concern
  requires_ancestor { Repository }

  # Public: Check if an organization or an owner, could be user, is enterprise managed
  sig { returns(T::Boolean) }
  def is_enterprise_managed?
    emu_org_owned? || emu_user_owned?
  end

  # Public Check if an organization or an owner, could be user, is enterprised managed
  sig { returns(T::Boolean) }
  def enterprise_managed_user_enabled?
    # this override allows for lining up naming with organizations and businesses.
    is_enterprise_managed?
  end

  # Public: Asynchronously check if the owner is an enterprise managed organization
  sig { returns(Promise[T::Boolean]) }
  def async_is_owner_enterprise_managed_organization?
    async_owner.then do |owner|
      owner.organization? && owner.async_enterprise_managed_user_enabled?
    end
  end

  # Public: Check if the repository is in the EMU owned organization
  sig { returns(T::Boolean) }
  def emu_org_owned?
    in_organization? && T.must(organization).enterprise_managed_user_enabled?
  end

  # Public: Check if the repository is owned by an EMU user
  sig { returns(T::Boolean) }
  def emu_user_owned?
    !in_organization? && T.must(owner).user? && T.must(owner).is_enterprise_managed?
  end

  # Public: A method to return enterprise managed business
  #
  sig { returns(T.nilable(Business)) }
  def enterprise_managed_business
    if in_organization?
      organization&.business if organization&.business&.enterprise_managed_user_enabled?
    elsif owner.is_a?(User)
      T.must(owner).enterprise_managed_business
    end
  end

  # Public: Async method to check if repository is enterprise managed
  #
  # Returns Promise with Business
  sig { returns(Promise[T.nilable(Business)]) }
  def async_enterprise_managed_business
    if organization_id?
      async_organization.then do |org|
        org&.async_business.then do |business|
          business if business&.enterprise_managed_user_enabled?
        end
      end
    else
      async_owner.then do |owner|
        if owner.is_a?(User)
          owner.async_enterprise_managed_business
        end
      end
    end
  end

  # Returns the business id of the owner of this repo if the owner is an organization with a business
  # or if the owner is a enterprise managed user. Returns nil otherwise.
  sig { returns(T.nilable(Integer)) }
  def business_id
    return GitHub.global_business&.id if GitHub.enterprise?

    if owner&.organization?
      owner&.business&.id
    elsif owner&.user?
      owner&.enterprise_managed_business&.id
    else
      nil
    end
  end

  # Returns "Organization" or "User"
  sig { returns(String) }
  def owner_type
    T.must(owner.class.name)
  end
end
