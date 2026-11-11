# typed: strict
# frozen_string_literal: true

# The Propagatable module is responsible for defining methods that allow policies to propagate the business
# value from a business to its organizations.

module Copilot
  module Policies
    module Concerns
      module Business
        module Propagatable
          extend T::Helpers
          include Copilot::PolicyInterface

          # in order to propagate, the org policy has to be mutable
          requires_ancestor { Copilot::Policies::Concerns::Organization::Mutable }

          abstract!

          sig { overridable.returns(T::Boolean) }
          def send_user_emails_on_propagation?
            true
          end

          sig { params(business: Copilot::Business, org: Copilot::Organization, send_email: T::Boolean).void }
          def propagate_to_org(business, org, send_email:)
            return if business.is_standalone_business?

            previous_value = value(org)

            rules_enabled = self.is_a?(Ruleable) && setting_rules_supported_policy?
            inherited_value = self.is_a?(Ruleable) && rules_enabled ? inherited_value(org) : value(business)
            no_policy = rules_enabled ? inherited_value == "no_policy" : no_policy?(business)

            # Skip propagation if business has no policy, but still send admin emails
            if no_policy
              # Send emails to org admins to notify them the business policy changed to no_policy
              if send_email && self.is_a?(Copilot::Policies::Concerns::Business::Mailable)
                T.bind(self, Copilot::Policies::Concerns::Business::Mailable)
                send_policy_updated_email_to_admins(org, value: inherited_value, previous_value: previous_value)
              end
              return
            end

            # propagate the business policy to the org
            # By default, send user emails unless the policy opts out
            update_org(org, inherited_value, force: true, send_email: send_email && send_user_emails_on_propagation?)

            # Send emails to org admins when propagating from business
            if send_email && self.is_a?(Copilot::Policies::Concerns::Business::Mailable)
              T.bind(self, Copilot::Policies::Concerns::Business::Mailable)
              send_policy_updated_email_to_admins(org, value: inherited_value, previous_value: previous_value)
            end
          end

          # this is basically just `update_org`, but it always forces and doesn't load the config for the org (unless its loaded in `available_for?`)
          sig { overridable.params(copilot_org: Copilot::Organization, config: Copilot::Configuration, value: String, previous_value: String, send_email: T::Boolean).void }
          def propagate_to_org_candidate(copilot_org, config, value, previous_value, send_email: true)
            # don't allow updates if the policy is not available for the org
            return unless available_for?(copilot_org)

            # don't allow setting to unconfigured in the paved path
            return if value == config_values[:unconfigured]

            update!(config, value)

            # update datadog counters
            GitHub.dogstats.increment(
              "copilot.settings.#{config_name}_#{value}",
              tags: ["type:organization"],
            )
            GitHub.dogstats.increment(
              "copilot.settings.updated",
              tags: ["type:organization", "policy_name:#{config_name}", "policy_value:#{value}"]
            )

            post_organization_update(copilot_org, value)

            # Send user emails if configured and the policy has Organization::Mailable
            if send_email && send_user_emails_on_propagation? && self.is_a?(Copilot::Policies::Concerns::Organization::Mailable)
              T.bind(self, Copilot::Policies::Concerns::Organization::Mailable)
              send_policy_updated_email(copilot_org, value: value, previous_value: previous_value)
            end

            # Send admin emails if the policy has Business::Mailable
            if send_email && self.is_a?(Copilot::Policies::Concerns::Business::Mailable)
              T.bind(self, Copilot::Policies::Concerns::Business::Mailable)
              send_policy_updated_email_to_admins(copilot_org, value: value, previous_value: previous_value)
            end
          end
        end
      end
    end
  end
end
