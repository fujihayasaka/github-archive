# typed: strict
# frozen_string_literal: true

# The Business::Mailable module is responsible for defining methods that enable sending emails to org admins
# when a business (enterprise) policy is updated and propagated to organizations.

module Copilot
  module Policies
    module Concerns
      module Business
        module Mailable
          extend T::Helpers
          include Copilot::PolicyInterface

          abstract!

          sig { abstract.params(org: ::Organization, admin: ::User).void }
          def send_policy_enabled_email_to_admin(org, admin); end

          sig { abstract.params(org: ::Organization, admin: ::User).void }
          def send_policy_no_policy_email_to_admin(org, admin); end

          sig { abstract.params(org: ::Organization, admin: ::User).void }
          def send_policy_disabled_email_to_admin(org, admin); end

          sig { overridable.params(org: Copilot::Organization).returns(T::Boolean) }
          def skip_admin_email?(org)
            false
          end

          # Send emails to org admins when business policy is propagated to the org
          sig { params(copilot_org: Copilot::Organization, value: String, previous_value: String).void }
          def send_policy_updated_email_to_admins(copilot_org, value:, previous_value:)
            return if skip_admin_email?(copilot_org)

            org = copilot_org.organization_object

            # Send appropriate email to all admins based on the transition
            # When transitioning TO no_policy we notify admins they now control the policy
            if value == config_values[:no_policy]
              # Only send no_policy emails if transitioning from a configured state
              # Don't send if already in no_policy or unconfigured
              if previous_value == config_values[:enabled] || previous_value == config_values[:disabled]
                org.admins.each do |admin|
                  send_policy_no_policy_email_to_admin(org, admin)
                end
              end
            elsif value == config_values[:disabled] && previous_value == config_values[:enabled]
              org.admins.each do |admin|
                send_policy_disabled_email_to_admin(org, admin)
              end
            elsif value == config_values[:enabled]
              org.admins.each do |admin|
                send_policy_enabled_email_to_admin(org, admin)
              end
            end
          end
        end
      end
    end
  end
end
