# typed: strict
# frozen_string_literal: true

# The Twirpable concern defines methods for serializing policy values for Twirp responses.
# It includes the UserCacheable concern to provide caching functionality for user policy values,
# which allows for efficient retrieval of policy values without needing to re-compute inheritance rules.
# This concern should be included in any policy that will need to be accessed via Twirp.

module Copilot
  module Policies
    module Concerns
      module Twirpable
        extend T::Helpers
        include Copilot::PolicyInterface

        include Copilot::Policies::Concerns::User::Cacheable

        abstract!

        # values used for twirp serialization
        sig do abstract.returns({
            enabled: Integer,
            disabled: Integer,
            no_policy: Integer,
            unconfigured: Integer,
            invalid: Integer
          })
        end
        private def twirp_values; end

        sig { overridable.returns(Symbol) }
        def twirp_key
          (config_name + "_setting").to_sym
        end

        sig { params(public_user: Copilot::Public::User, copilot_user: Copilot::User).returns(Integer) }
        def twirp_value(public_user, copilot_user)
          return twirp_values[:invalid] unless available_for?(copilot_user)

          case cached_value(public_user)
          when config_values[:enabled]
            twirp_values[:enabled]
          when config_values[:disabled]
            twirp_values[:disabled]
          when config_values[:unconfigured]
            twirp_values[:unconfigured]
          when config_values[:no_policy]
            twirp_values[:no_policy]
          else
            twirp_values[:invalid]
          end
        end
      end
    end
  end
end
