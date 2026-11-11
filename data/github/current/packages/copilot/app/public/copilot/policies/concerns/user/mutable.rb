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

          sig { abstract.params(copilot_user: Copilot::User).returns(PolicyDescription) }
          def user_setting_description(copilot_user); end

          sig { overridable.params(copilot_user: Copilot::User).returns(T::Boolean) }
          def editable_by_user?(copilot_user)
            viewable_by_user?(copilot_user) && copilot_user.can_modify_copilot_settings?
          end

          sig { overridable.params(copilot_user: Copilot::User).returns(T::Boolean) }
          def viewable_by_user?(copilot_user)
            available_for?(copilot_user)
          end

          sig { overridable.params(copilot_user: Copilot::User, value: String).void }
          def update_user(copilot_user, value)
            return unless available_for?(copilot_user)

            update!(copilot_user.configuration, value)

            # update datadog counters
            GitHub.dogstats.increment(
              "copilot.settings.#{config_name}_#{value}",
              tags: ["type:user"],
            )
            GitHub.dogstats.increment(
              "copilot.settings.updated",
              tags: ["type:user", "policy_name:#{config_name}", "policy_value:#{value}"]
            )

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
