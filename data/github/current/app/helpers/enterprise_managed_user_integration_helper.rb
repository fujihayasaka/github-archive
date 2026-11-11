# typed: true
# frozen_string_literal: true

module EnterpriseManagedUserIntegrationHelper
  extend T::Helpers

  # Check if the current integration is owned by an EMU (Enterprise Managed User).
  #
  # Uses controller methods:
  # - integration: The integration being accessed
  #
  # Returns true if the integration is owned by an EMU, false otherwise.
  def integration_owned_by_emu?(integration)
    owner_is_enterprise_managed = if T.must(integration.owner).user?
      integration.owner&.is_enterprise_managed?
    else
      integration.owner&.enterprise_managed_user_enabled?
    end

    owner_is_enterprise_managed
  end

  # Check if the current user is allowed to interact with an EMU-owned integration. If the app is owned by an EMU,
  # and the user is not a member of the same enterprise, they will not be authorized to access the app.
  #
  # Uses controller methods:
  # - integration: The integration being accessed
  # - user: The user trying to access the integration
  #
  # Returns true if association is valid, false otherwise.
  def is_user_associated_with_emu_owner?(integration, user)
    owner_biz = if integration.owner.business?
      integration.owner
    elsif integration.owner.organization?
      integration.owner.business
    else
      integration.owner.enterprise_managed_business
    end

    user_biz = user.enterprise_managed_business

    user_biz == owner_biz
  end
end
