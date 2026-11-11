# typed: true
# frozen_string_literal: true

module BusinessUserAccounts
  class MemberView < Businesses::QueryView
    # query filters defined for QueryView
    attr_reader :role

    def filter_map
      BusinessesHelper::USER_ACCOUNT_MEMBERSHIP_QUERY_FILTERS
    end

    # For /enterprise_installations and /organizations routes:
    # - use the enterprise_user_accounts/XX/[action] route for server-only users (BusinessUserAccount not linked to a user)
    # - use /people/[login]/[action] route for cloud users (BusinessUserAccount linked to a user)
    def enterprise_installations_path(user_account, query: nil)
      if user_account.user.nil?
        url_params = [user_account.id]
        url_params << { query: query } unless query.nil?
        return urls.enterprise_installations_enterprise_user_account_path(*url_params)
      end

      url_params = [user_account.business, user_account.user]
      url_params << { query: query } unless query.nil?
      urls.enterprise_person_enterprise_installations_enterprise_path(*url_params)
    end

    def organizations_path(user_account, query: nil)
      if user_account.user.nil?
        url_params = [user_account.id]
        url_params << { query: query } unless query.nil?
        return urls.organizations_enterprise_user_account_path(*url_params)
      end

      url_params = [user_account.business, user_account.user]
      url_params << { query: query } unless query.nil?
      urls.enterprise_person_organizations_enterprise_path(*url_params)
    end

    def user_organizations_path(user, query: nil)
      return nil unless GitHub.enterprise?
      url_params = [GitHub.global_business, user]
      url_params << { query: query } unless query.nil?
      urls.enterprise_person_organizations_enterprise_path(*url_params)
    end

    def teams_path(user_account, query: nil)
      if user_account.user.nil?
        return nil
      end

      url_params = [user_account.business, user_account.user]
      url_params << { query: query } unless query.nil?
      urls.enterprise_person_teams_enterprise_path(*url_params)
    end

    def user_teams_path(user, query: nil)
      return nil unless GitHub.enterprise?
      url_params = [GitHub.global_business, user]
      url_params << { query: query } unless query.nil?
      urls.enterprise_person_teams_enterprise_path(*url_params)
    end
  end
end
