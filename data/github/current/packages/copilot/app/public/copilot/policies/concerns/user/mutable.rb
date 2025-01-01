# typed: strict
# frozen_string_literal: true

# The UserOperations module is responsible for enabling mutable operations on user policies.
module Copilot
  module Policies
    module Concerns
      module User
        module Mutable
          extend T::Helpers
          include Copilot::Policy

          abstract!

          sig { override.params(copilot_user: Copilot::User, value: String).void }
          def update_user(copilot_user, value)
            update!(copilot_user.configuration, value)
            post_user_update(copilot_user, value)
          end

          # noop to be optionally overridden
          sig { overridable.params(copilot_user: Copilot::User, value: String).void }
          def post_user_update(copilot_user, value); end
        end
      end
    end
  end
end
