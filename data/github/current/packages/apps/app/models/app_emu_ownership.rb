# typed: strict
# frozen_string_literal: true

module AppEmuOwnership
  extend T::Sig
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

  sig { returns(T.nilable(Business)) }
  def owner_enterprise_managed_business
    T.bind(self, T.any(OauthApplication, Integration))

    enterprise_managed_business_for(owner)
  end

  private

  # Private: Is the entity Enterprise managed?
  #
  # Returns a Boolean
  sig { params(entity: T.untyped).returns(T::Boolean) }
  def is_enterprised_managed?(entity)
    case entity
    when Business, Organization
      entity.enterprise_managed_user_enabled?
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
    when Organization
      entity.business
    when User
      entity.enterprise_managed_business
    end
  end
end
