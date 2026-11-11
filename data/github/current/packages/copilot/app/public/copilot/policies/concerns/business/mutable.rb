# typed: strict
# frozen_string_literal: true

# The Business::Mutable module is responsible for enabling mutable operations on business policies.

module Copilot
  module Policies
    module Concerns
      module Business
        module Mutable
          extend T::Helpers
          include Copilot::PolicyInterface

          abstract!

          sig { abstract.params(copilot_business: Copilot::Business).returns(PolicyDescription) }
          def business_setting_description(copilot_business); end

          sig { overridable.params(copilot_business: Copilot::Business).returns(T::Boolean) }
          def editable_by_business?(copilot_business)
            # by default, if you can see it you can edit it
            viewable_by_business?(copilot_business)
          end

          # whether or not to show this policy to the given business
          sig { overridable.params(copilot_business: Copilot::Business).returns(T::Boolean) }
          def viewable_by_business?(copilot_business)
            # by default, if the policy is available, show it.
            available_for?(copilot_business)
          end

          sig { overridable.params(copilot_business: Copilot::Business, value: String).void }
          def update_business(copilot_business, value)
            # ensure we can use this policy
            return unless available_for?(copilot_business)

            # standalone businesses do not have orgs, so they can not set to no_policy
            return if value == config_values[:no_policy] && copilot_business.is_standalone_business?

            # we should not allow setting the unconfigured value using this paved path
            return if value == config_values[:unconfigured]

            update!(copilot_business.configuration, value)

            # update datadog counters
            GitHub.dogstats.increment(
              "copilot.settings.#{config_name}_#{value}",
              tags: ["type:business"],
            )
            GitHub.dogstats.increment(
              "copilot.settings.updated",
              tags: ["type:business", "policy_name:#{config_name}", "policy_value:#{value}"]
            )

            post_business_update(copilot_business, value)

            Copilot::NewBatchUpdateOrgSettingsJob.perform_later(copilot_business.id, config_name.to_sym)
            Copilot::BatchUpdateEnterpriseUserSettingsJob.perform_later(copilot_business.business_object)
          end

          # noop to be optionally overridden
          sig { overridable.params(copilot_business: Copilot::Business, value: String).void }
          def post_business_update(copilot_business, value); end
        end
      end
    end
  end
end
