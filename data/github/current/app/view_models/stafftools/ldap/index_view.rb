# typed: true
# frozen_string_literal: true

module Stafftools
  module Ldap
    class IndexView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      def ldap_search_explanation
        message = []

        message << "This searches the external LDAP server directly. Users are found by their LDAP "
        message << helpers.content_tag(:strong, GitHub.ldap_profile_uid) # rubocop:disable Rails/ViewModelHTML

        if (groups = GitHub.ldap_auth_groups).present?
          if groups.size == 1
            message << " and are restricted to the "
            message << helpers.content_tag(:strong, groups.first) # rubocop:disable Rails/ViewModelHTML
            message << " group"
          elsif groups.size == 2
            message << " and are restricted to the "
            message << helpers.content_tag(:strong, groups.first) # rubocop:disable Rails/ViewModelHTML
            message << " and "
            message << helpers.content_tag(:strong, groups.last) # rubocop:disable Rails/ViewModelHTML
            message << " groups"
          else
            message << " and are restricted to the "
            groups[0...-1].each do |group|
              message << helpers.content_tag(:strong, group) # rubocop:disable Rails/ViewModelHTML
              message << ", "
            end
            message << " and "
            message << helpers.content_tag(:strong, groups.last) # rubocop:disable Rails/ViewModelHTML
            message << " groups"
          end
        end

        message << ". User accounts are created automatically when they login for the first time, so manually creating each account isn’t required."
        if GitHub.ldap_admin_group.present?
          message << " Users in the "
          message << helpers.content_tag(:strong, GitHub.ldap_admin_group) # rubocop:disable Rails/ViewModelHTML
          message << " group will be automatically promoted to "
          message << helpers.content_tag(:em, "site administrators") # rubocop:disable Rails/ViewModelHTML
          message << "."
        end

        helpers.safe_join(message)
      end
    end
  end
end
