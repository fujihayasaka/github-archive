# typed: strict
# frozen_string_literal: true

# The User::Cacheable module is responsible for providing a way to cache policy values for a given user.
# This module is used when retrieving policy values in Twirp without needing to re-compute the inheritance rules,
# which can be expensive. While included in the Twirpable concern, it can also be used independently if you find
# yourself needing to cache user policy values in other contexts.

module Copilot
  module Policies
    module Concerns
      module User
        module Cacheable
          extend T::Helpers
          include Copilot::Policy

          abstract!

          sig { params(user: Copilot::Public::User).returns(T.nilable(String)) }
          def cached_value(user)
            user.policy_value(config_name.to_sym)
          end
        end
      end
    end
  end
end
