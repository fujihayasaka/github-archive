# typed: false
# frozen_string_literal: true

module GitHub
  module RouteHelpers

    # For use when the User could be a Bot belonging to an integration. Links to the
    # integration's stafftools when possible but there are currently no stafftools
    # for integrations that belong to Businesses.
    def gh_stafftools_user_path(user_or_bot)
      unless user_or_bot.bot?
        return stafftools_user_path(user_or_bot)
      end

      integration = user_or_bot.integration
      gh_stafftools_app_path(integration.owner, integration)
    end

    def gh_stafftools_app_path(owner, integration)
      if owner.is_a?(Business)
        stafftools_business_app_path(owner, integration)
      else
        stafftools_user_app_path(owner, integration)
      end
    end

    def gh_stafftools_user_gpg_key_path(key)
      stafftools_user_gpg_key_path(key.user, key)
    end

    def gh_database_stafftools_user_gpg_key_path(key)
      database_stafftools_user_gpg_key_path(key.user, key)
    end

    def gh_stafftools_app_installation_path(installation)
      target = installation.target

      if target.is_a?(Business)
        stafftools_enterprise_integration_installation_path(target, installation)
      else
        stafftools_user_installation_path(target, installation)
      end
    end

  end
end
