# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class AssignableUsers < Platform::Resolvers::Users
      include Helpers::AssigneesHelper

      argument :query, String, "Filters users with query on user name and login.", required: false
      argument :login_names, String, "A comma separated list of login names to filter users by. Only the first #{MAX_LOGIN_NAMES_LENGTH} logins will be used.", required: false, visibility: :internal

      def resolve(**arguments)
        context[:permission].async_can_get_full_repo?(object).then do |can_get_full_repo|
          if can_get_full_repo
            if arguments[:login_names].present?
              logins = extract_logins_from_string(arguments[:login_names])
              get_valid_assignees_from_logins(object, logins)
            else
              ids = object.visible_available_assignee_ids(context[:viewer], limit: Issue::AssignmentDependency::PLATFORM_ASSIGNEE_LIMIT)

              includes_associations = []
              includes_associations << :business_user_accounts if GitHub.multi_tenant_enterprise?

              tenant_id = GitHub::CurrentTenant.get.try(:id) || User::MultiTenantEnterpriseManagedDependency::NON_ENTERPRISE_MANAGED_BUSINESS_ID
              scope = User.where(id: ids, business_id: tenant_id).includes(includes_associations)

              scope = filter_spam(scope.order("display_login"))

              query = arguments[:query].to_s.strip

              if query.present?
                scope = scope.like_display_login_or_profile_name(query)
              end

              scope
            end
          else
            ArrayWrapper.new([])
          end
        end
      end
    end
  end
end
