# typed: strict
# frozen_string_literal: true

module AppEmuOwnership
  extend T::Helpers

  sig { params(target: T.any(Business, User, Organization)).returns(T::Boolean) }
  def valid_target?(target)
    T.bind(self, T.any(OauthApplication, Integration))
    # Integrations owned by EMUs cannot be installed outside of the Enterprise
    if is_enterprised_managed?(owner) && GitHub.flipper[:integration_installable_on_with_emus_check].enabled?(self)
      # Return false early if the target isn't Enterprises Managed as we already know
      # there is a mismatch between the owning Enterprise and the target Enterprise.
      return false unless is_enterprised_managed?(target)
      # Compare the Integration owner and the target to ensure that both are managed by
      # the same Enterprise
      return false unless owner_enterprise_managed_business == enterprise_managed_business_for(target)
    end

    true
  end

  sig { returns(T::Boolean) }
  def owner_is_enterprise_managed?
    T.bind(self, T.any(OauthApplication, Integration))
    is_enterprised_managed?(self.owner)
  end

  sig { returns(Promise[T.nilable(Business)]) }
  def async_owner_enterprise_managed_business
    T.bind(self, T.any(OauthApplication, Integration))

    self.async_owner.then do |owner|
      next Promise.resolve(nil) unless owner

      enterprise_managed_business_for(owner)
    end
  end

  sig { returns(T.nilable(Business)) }
  def owner_enterprise_managed_business
    T.bind(self, T.any(OauthApplication, Integration))

    if GitHub.flipper[:remove_hidden_from_public_integration_installation].enabled?
      async_owner_enterprise_managed_business.sync
    else
      enterprise_managed_business_for(owner)
    end
  end

  private

  # Private: Is the entity Enterprise managed?
  #
  # Returns a Boolean
  sig { params(entity: T.untyped).returns(T::Boolean) }
  def is_enterprised_managed?(entity)
    case entity
    when Business
      entity.enterprise_managed_user_enabled?
    when Organization
      # Load the business to make the platform loaders happy.
      entity.async_business.then do
        entity.enterprise_managed_user_enabled?
      end.sync
    when User
      entity.is_enterprise_managed?
    else
      false
    end
  end

  # Private: Return the Enterprise Managed Business for the given entity
  #
  # Returns a Business or nil
  sig { params(entity: T.untyped).returns(T.nilable(Business)) }
  def enterprise_managed_business_for(entity)
    return unless is_enterprised_managed?(entity)

    case entity
    when Business
      entity
    else
      Business.enterprise_managed_business_for(resource: entity)
    end
  end
end
