# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class CampusExperts
      CAMPUS_EXPERTS_DOCUMENTATION = "ec0ff7f231f9ea51dcf9".freeze
      CAMPUS_EXPERTS_PROFILE       = "b71214e719d5771ed590".freeze

      def self.id_finder(key)
        ->() {
          OauthApplication.find_by(
            key: key,
          )&.id
        }
      end

      DOCUMENTATION = {
        alias: :campus_experts_documentation,
        id: id_finder(CAMPUS_EXPERTS_DOCUMENTATION),
        inherits: [],
        capabilities: {
          operated_by_github: true, # Preserves behavior that used to be hard-coded in `OauthApplication`
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: [],
      }

      PROFILE = {
        alias: :campus_experts_profile,
        id: id_finder(CAMPUS_EXPERTS_PROFILE),
        inherits: [],
        capabilities: {
          operated_by_github: true, # Preserves behavior that used to be hard-coded in `OauthApplication`
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: [],
      }

      OAUTH_APPS = [
        DOCUMENTATION,
        PROFILE,
      ].freeze
    end
  end
end
