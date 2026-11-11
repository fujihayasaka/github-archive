# typed: true
# frozen_string_literal: true

module Permissions
  module Enumerators
    class GrantableManageOrganizationApps < Permissions::Enumerator
      def actor_ids
        # These enumerators are not used anymore and will be removed in an upcoming PR.
        # Please use Apps::ManagementHelper.user_ids_grantable_for_app_manager_role
        raise NotImplementedError, "This method is deprecated"
      end
    end
  end
end
