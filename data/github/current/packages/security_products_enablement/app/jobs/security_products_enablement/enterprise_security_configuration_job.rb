# typed: true
# frozen_string_literal: true

module SecurityProductsEnablement
  class EnterpriseSecurityConfigurationJob < ApplicationJob
    include GitHub::Memoizer
    VALID_ACTIONS = %i[apply detach update]

    queue_as :security_configurations

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    sig do
      params(
        security_configuration_id: T.nilable(Integer),
        enterprise_id: Integer,
        actor_id: Integer,
        action: Symbol,
        override_existing_config: T::Boolean,
        user_session_id: T.nilable(Integer),
        options: T::Hash[Symbol, T.untyped]
      ).void
    end
    def perform(
      security_configuration_id:,
      enterprise_id:,
      actor_id:,
      action:,
      override_existing_config: false,
      user_session_id: nil,
      options: {}
    )
      GitHub.logger.info("Beginning job")

      raise ArgumentError, "Invalid action: #{action}" unless VALID_ACTIONS.include?(action)

      if security_configuration.nil? && action != :detach
        GitHub.logger.info("Enterprise security configuration not found.")
        return
      end

      enterprise = self.enterprise
      if enterprise.nil?
        GitHub.logger.info("Enterprise not found.")
        return
      end

      actor = self.actor
      if actor.nil?
        GitHub.logger.info("Actor not found.")
        return
      end

      enterprise.organizations.pluck(:id).each do |org_id|
        SecurityProductsEnablement::OrganizationSecurityConfigurationJob.perform_later(
          security_configuration_id:,
          organization_id: org_id,
          actor_id:,
          action:,
          repository_ids: nil,
          repository_query: nil,
          override_existing_config:,
          user_session_id:,
          options:
        )
      end
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      tags = {
        "gh.enterprise.id": arguments.dig(0, :enterprise_id),
        "gh.enduser.id": arguments.dig(0, :actor_id),
        "gh.enduser.login": actor&.display_login,
        "gh.security_configuration.id": arguments.dig(0, :security_configuration_id),
        "gh.security_configuration.action": arguments.dig(0, :action),
        "gh.security_configuration.user_session_id": arguments.dig(0, :user_session_id),
        "gh.security_configuration.org_job.override_existing_config": arguments.dig(0, :override_existing_config),
        "gh.security_configuration.org_job.options": arguments.dig(0, :options)
      }

      super.merge(tags)
    end

    sig { returns T.nilable(SecurityConfiguration) }
    memoize def security_configuration
      security_configuration_id = arguments.dig(0, :security_configuration_id)
      return if security_configuration_id.nil?

      if security_configuration_id == SecurityConfiguration.github_recommended_configuration&.id
        SecurityConfiguration.github_recommended_configuration
      else
        SecurityConfiguration.find_by(id: security_configuration_id, target_type: "Business")
      end
    end

    sig { returns(T.nilable(Business)) }
    memoize def enterprise
      enterprise_id = arguments.dig(0, :enterprise_id)
      return if enterprise_id.nil?
      Business.find_by(id: enterprise_id)
    end

    sig { returns(T.nilable(User)) }
    memoize def actor
      actor_id = arguments.dig(0, :actor_id)
      return if actor_id.nil?
      User.find_by(id: actor_id)
    end

    sig { returns(T.nilable(UserSession)) }
    memoize def user_session
      user_session_id = arguments.dig(0, :user_session_id)
      return if user_session_id.nil?
      UserSession.find_by(id: user_session_id)
    end
  end
end
