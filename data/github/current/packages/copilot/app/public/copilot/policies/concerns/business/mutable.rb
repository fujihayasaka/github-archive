# typed: strict
# frozen_string_literal: true

# The Business::Mutable module is responsible for enabling mutable operations on business policies.

module Copilot
  module Policies
    module Concerns
      module Business
        module Mutable
          extend T::Helpers
          include Copilot::Policy

          abstract!

          sig { overridable.params(copilot_business: Copilot::Business, value: String).void }
          def update_business(copilot_business, value)
            # ensure we can use this policy
            return unless available_for?(copilot_business)

            # standalone businesses do not have orgs, so they can not set to no_policy
            return if value == config_values[:no_policy] && copilot_business.is_standalone_business?

            # we should not allow setting the unconfigured value using this paved path
            return if value == config_values[:unconfigured]

            update!(copilot_business.configuration, value)

            post_business_update(copilot_business, value)

            Copilot::NewBatchUpdateOrgSettingsJob.perform_later(copilot_business.id, config_name.to_sym)
          end

          # noop to be optionally overridden
          sig { overridable.params(copilot_business: Copilot::Business, value: String).void }
          def post_business_update(copilot_business, value); end
        end
      end
    end
  end
end
