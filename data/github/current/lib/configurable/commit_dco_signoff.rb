# typed: false
# frozen_string_literal: true

# Configures whether to enable dco signoff setting for a repository
module Configurable
  module CommitDcoSignoff

    KEY = "dco_signoff".freeze

    # Enable DCO signoff for specific repository.
    def enable_dco_signoff(actor:)
      raise ArgumentError, "can only be configured on a Repository" unless self.is_a?(Repository)
      config.enable(KEY, actor)
    end

    # Reset DCO signoff for specific repository.
    def reset_dco_signoff(actor:)
      raise ArgumentError, "can only be configured on a Repository" unless self.is_a?(Repository)
      config.delete(KEY, actor)
    end

    # Enable DCO signoff for an organization.
    # We use force (!) here to apply the setting to all repositories.
    def enable_dco_signoff_for_all(actor:)
      raise ArgumentError, "can only be configured on an Organization" unless self.is_a?(Organization)
      config.enable!(KEY, actor)
    end

    # Reset DCO signoff for an organization.
    # Deleting the setting for an organization will remove override for all repositories and bring them to their previous values.
    def reset_dco_signoff_for_all(actor:)
      raise ArgumentError, "can only be configured on an Organization" unless self.is_a?(Organization)
      config.delete(KEY, actor)
    end

    # Determines whether the DCO signoff policy enabled for given repository/organization.
    # Forked repositories copy the policy from their parent during forking.
    def dco_signoff_enabled?
      config.enabled?(KEY)
    end
  end
end
