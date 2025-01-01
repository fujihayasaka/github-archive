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
          include Copilot::Policy

          # in order to propagate, the org policy has to be mutable
          include Copilot::Policies::Concerns::Organization::Mutable

          abstract!

          sig { abstract.params(business: Copilot::Business, org: Copilot::Organization).returns(T::Boolean) }
          def propagate_business_updates?(business, org); end

          sig { params(business: Copilot::Business, org: Copilot::Organization, send_email: T::Boolean).void }
          def propagate_to_org(business, org, send_email:)
            return if business.is_standalone_business?
            return if no_policy?(business)

            # propagate the business policy to the org
            update_org(org, value(business), force: true, send_email:)
          end
        end
      end
    end
  end
end
