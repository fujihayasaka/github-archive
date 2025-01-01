# typed: true
# frozen_string_literal: true

# Configures allowing outside collaborators to request access from OAuth and GitHub Apps
module Configurable
  module OutsideCollaboratorsCanRequestThirdPartyAccess
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { Instrumentation::Model }

    KEY = T.let("disallow_third_party_access_requests_from_outside_collaborators", String)

    def allow_third_party_access_requests_from_outside_collaborators(actor:)
      config.disable!(KEY, actor, true)

      self.instrument("allow_third_party_access_requests_from_outside_collaborators_enabled", {
        actor: actor,
      })
    end

    def disallow_third_party_access_requests_from_outside_collaborators(actor:)
      config.enable!(KEY, actor, false)

      self.instrument("allow_third_party_access_requests_from_outside_collaborators_disabled", {
        actor: actor,
      })
    end

    def allows_third_party_access_requests_from_outside_collaborators?
      !config.enabled?(KEY)
    end

    def denies_third_party_access_requests_from_outside_collaborators?
      !allows_third_party_access_requests_from_outside_collaborators?
    end
  end
end
