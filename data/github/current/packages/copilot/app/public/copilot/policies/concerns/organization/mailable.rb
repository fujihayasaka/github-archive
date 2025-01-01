# typed: strict
# frozen_string_literal: true

# The Mailable module is responsible for defining methods that enable sending emails upon updating a policy
# for an organization.

module Copilot
  module Policies
    module Concerns
      module Organization
        module Mailable
          extend T::Helpers
          include Copilot::Policy

          abstract!

          sig { abstract.params(org: ::Organization, user: ::User).void }
          def send_policy_enabled_email(org, user); end

          sig { abstract.params(org: ::Organization, user: ::User).void }
          def send_policy_disabled_email(org, user); end

          sig { overridable.params(org: Copilot::Organization).returns(T::Boolean) }
          def skip_email?(org)
            false
          end

          sig { params(copilot_org: Copilot::Organization, value: String, previous_value: String).void }
          def send_policy_updated_email(copilot_org, value:, previous_value:)
            return if skip_email?(copilot_org)
            org = copilot_org.organization_object
            if value == config_values[:disabled] && previous_value == config_values[:enabled]
              Copilot::Seat.for_organization(org).each do |seat|
                send_policy_disabled_email(org, seat.assigned_user)
              end
            elsif value == config_values[:enabled]
              Copilot::Seat.for_organization(org).each do |seat|
                send_policy_enabled_email(org, seat.assigned_user)
              end
            end
          end

        end
      end
    end
  end
end
