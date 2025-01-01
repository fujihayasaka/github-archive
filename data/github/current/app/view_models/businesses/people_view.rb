# typed: true
# frozen_string_literal: true

module Businesses
  class PeopleView < Businesses::QueryView
    include EnterpriseManagedUsersHelper
    include LicensingHelper

    # query filters defined for QueryView
    attr_reader :business, :role, :account_type, :organizations, :teams, :deployment, :license, :two_factor_status, :two_factor_warning_banner, :filter_help_url, :selected_user_ids, :owner_actor, :cost_center

    def initialize(**args)
      super(args)
      @business = args[:business]
      @selected_user_ids ||= args[:selected_user_ids]
      @owner_actor = args[:owner_actor]
    end

    # Public - generate a link for the given member.
    # If member is a User object, just returns a link to the user profile page - this only happens
    # in a server environment.
    # In dotcom, member will be a BusinessUserAccount. Then, return:
    #  - a Businesses::People::OrganizationsController URL, if account is for a cloud user (linked to a User)
    #  - a BusinessUserAccounts::EnterpriseInstallationsController URL, if account is for a server-only
    #      user (not linked to a User). We could link to the #organizations page also, but since this
    #      is a server-only member, we know they don't belong to any dotcom organizations.
    #
    # member  -   Enterprise member (either a User - GHES or a BusinessUserAccount - GHEC)
    #
    # Returns: url string
    def member_link(member)
      if member.is_a?(User)
        if GitHub.enterprise?
          return urls.enterprise_person_organizations_enterprise_path(GitHub.global_business, member)
        else
          return urls.user_path(member)
        end
      end
      return urls.enterprise_installations_enterprise_user_account_path(member.id) if member.user.nil?
      urls.enterprise_person_organizations_enterprise_path(member.business, member.user)
    end

    def organization_member_link_data_options(member)
      return {} unless member

      case member
      when ::User
        helpers.hovercard_data_attributes_for_user(member)
      when ::BusinessUserAccount
        helpers.hovercard_data_attributes_for_business_user_account(member)
      end
    end

    def membership_count_label(org_count, server_count)
      parts = []
      parts << helpers.pluralize(org_count, "organization") if org_count > 0
      parts << helpers.pluralize(server_count, "server") if server_count > 0

      parts.to_sentence
    end

    def filter_map
      BusinessesHelper::MEMBERS_QUERY_FILTERS
    end

    def display_two_factor_filter_warning?
      # two_factor_status can only be :enabled, :disabled, or nil, at this point
      if two_factor_status.present? && @business.enterprise_installations.any?
        # might need to check that we're not in GitHub enterprise mode
        @two_factor_warning_banner ||= "Members present only on your server instance(s) will not be reflected in the filtered results because you are filtering by two-factor authentication status."
        @filter_help_url ||= "#{GitHub.help_url}/admin/user-management/managing-users-in-your-enterprise/viewing-people-in-your-enterprise"
        return true
      end
      false
    end

    def display_cost_center_error_warning?
      show_cost_center?(@business) && @business.cost_centers.nil?
    end

    def subtitle_for_member(member)
      return unless member.name.present?

      user = member.is_a?(BusinessUserAccount) ? member.user : member
      user&.display_login
    end

    def selected_users
      return @selected_users if defined? @selected_users

      provided_ids = @selected_user_ids || []
      @selected_users = User.where(id: provided_ids & allowed_user_ids)
    end

    def allowed_user_ids
      if GitHub.single_business_environment?
        @business.filtered_members(current_user).pluck(:id)
      else
        @business.filtered_members(current_user).includes(:user).map { |account| account&.user&.id }.compact
      end
    end

    def owner_actor?
      @owner_actor
    end

    def basic?
      @business.seats_plan_basic?
    end

    def copilot_enabled?
      @business.copilot_licensing_enabled?
    end

    def show_remove?
      @role != "unaffiliated"
    end
  end
end
