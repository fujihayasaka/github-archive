# typed: strict
# frozen_string_literal: true

# The Organization::Mutable module is responsible for enabling mutable operations on organization policies.

module Copilot
  module Policies
    module Concerns
      module Organization
        module Mutable
          extend T::Helpers
          include Kernel
          include Copilot::Policy

          abstract!

          # whether or not to show this policy to the given organization
          sig { overridable.params(copilot_org: Copilot::Organization).returns(T::Boolean) }
          def viewable_by_org?(copilot_org)
            # by default, if the policy is available, show it.
            available_for?(copilot_org)
          end

          sig { overridable.params(copilot_org: Copilot::Organization, value: String, force: T::Boolean, send_email: T::Boolean).void }
          def update_org(copilot_org, value, force: false, send_email: true)
            # don't allow updates if the policy is not available for the org
            return unless available_for?(copilot_org)

            # we normally should not let the org update their policy if the orgs business has a policy set
            # however, we allow overriding this behavior in order to enable policy propagation from business to org
            return if org_policy_inherited?(copilot_org) && !force

            # don't allow setting to unconfigured in the paved path
            return if value == config_values[:unconfigured]

            previous_value = value(copilot_org)

            update!(copilot_org.configuration, value)
            post_organization_update(copilot_org, value)

            if self.is_a?(Copilot::Policies::Concerns::Organization::Mailable) && send_email
              T.bind(self, Copilot::Policies::Concerns::Organization::Mailable)
              send_policy_updated_email(copilot_org, value: value, previous_value: previous_value)
            end

            Copilot::BatchUpdateUserSettingsJob.perform_later(copilot_org.id)
          end

          # noop to be optionally overridden
          sig { overridable.params(copilot_org: Copilot::Organization, value: String).void }
          def post_organization_update(copilot_org, value); end
        end
      end
    end
  end
end
