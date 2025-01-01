# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module ConditionalAccess
      extend T::Helpers

      requires_ancestor { Object }

      # Compute all accounts that the user is unauthorized to access due to Conditional Access Policies.
      # Considers orgs that the user belongs to directly (member of the org) and indirectly (via business membership).
      #  - user: the current User. Can be nil for anonymous requests.
      #  - cap_filter: a ConditionalAccess::Filter instance.
      # Returns an Array of User/Organization IDs.
      def unauthorized_account_ids(user, cap_filter)
        raise Errors::Internal, "cap_filter can't be nil" unless cap_filter
        resources = user&.resources_for_cap_filter(
          direct_and_indirect_orgs: true
        )
        cap_filter.unauthorized_resource_ids(resources)
      end
    end
  end
end
