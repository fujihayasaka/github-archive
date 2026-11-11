# typed: true
# frozen_string_literal: true

module Stafftools
  # This module is used via the authorized? function, it returns a bool indicating whether or
  # not a user can access a portion of stafftools. Authorization is determined by comparing the roles
  # assigned to the user via stafftools_roles to the access roles set for the controller/action
  # in `config/stafftools_permissions.yml`.
  #
  # If you're seeing 403s in stafftools and require escalated privileges for local development,
  # try `bin/rake stafftools_auth:set_up_roles_for_dev`.
  #
  module AccessControl
    extend self
    include Kernel

    class RuleValidationError < StandardError
    end

    # Main authorization checking function, declared at module level
    # params:
    # user - Instance of activerecord User
    # area_description - Object - Expected to contain keys
    #        describing the controller and action to access as strings
    def authorized?(user, area_description)
      return false unless user.site_admin?
      return true if GitHub.enterprise?

      controller_name = area_description.fetch(:controller)
      action = area_description.fetch(:action)

      controller_settings = find_controller_permissions(controller_name)
      allowed_roles = get_access_roles(controller_settings, action)
      user_access = allowed_roles & get_user_roles(user)

      user_access.any?
    end

    # Api authorization check
    # params:
    # user - Instance of ActiveRecord user.
    # area_description - Object - Expects keys
    #   • route_pattern - a string representing an api endpoint. I.E. /staff/users
    #   • request_method - the method used in the request. GET, POST, PUT etc
    def api_authorized?(user, area_description)
      return false unless user&.user? && user.site_admin?
      return true if GitHub.enterprise?

      route_pattern = area_description.fetch(:route_pattern)
      request_method = area_description.fetch(:request_method)

      # Get route level permissions
      route_access_settings = find_rest_api_permissions(route_pattern)

      # Get the allowed permissions
      allowed_roles = get_access_roles(route_access_settings, request_method, action_namespace: "request_method")

      # Check for user access
      user_access = allowed_roles & get_user_roles(user)

      user_access.any?
    end

    def permissions
      @@permissions ||= load_permissions
    end

    def proxima_okta_map
      @@proxima_okta_map ||= load_proxima_okta_map
    end

    def load_permissions
      file_path = Rails.root.join("config", "stafftools_permissions.yml")
      Psych.safe_load(File.read(file_path))["permissions"]
    end

    def load_proxima_okta_map
      file_path = Rails.root.join("config", "stafftools_permissions.yml")
      Psych.safe_load(File.read(file_path))["proxima_okta_group"]
    end

    # Checks for the existence of a user's external group memberships and upgrades or revokes
    # stafftools roles if membership has changed. If all roles are removed, it will revoke stafftools access altogether
    # TODO : This will move to a call back based function in the future, once ExternalIdentityGroupMembership
    #        updates it's delete_all to use delete or other call back features
    def upgrade_stafftools_role_via_external_groups(user)
      return unless GitHub.multi_tenant_enterprise? && GitHub::CurrentTenant.stafftools_tenant?
      return unless user.can_become_staff?

      stafftools_tenant = GitHub::CurrentTenant.get

      stafftools_slug = stafftools_tenant.slug
      external_provider = stafftools_tenant.external_provider
      return unless external_provider

      # gets the map of all the stafftools roles and their corresponding okta names
      proxima_okta_map.each do |sr|
        okta_name = sr["okta_name"]
        okta_always_on_name = sr["okta_always_on_name"]
        role_name = sr["role_name"]
        group = ExternalGroup.by_provider(external_provider).where(display_name: [okta_name, "#{stafftools_slug}-#{okta_name}"]).first
        always_on_group = ExternalGroup.by_provider(external_provider).where(display_name: [okta_always_on_name, "#{stafftools_slug}-#{okta_always_on_name}"]).first

        # check if the external_group is defined for this tenant
        next if !group && !always_on_group

        role = StafftoolsRole.find_by(name: role_name)

        # check if the role is defined in stafftools
        next unless role

        jit_access = group && group.active_user?(user)
        always_on_access = always_on_group && always_on_group.active_user?(user)

        # assign or revoke the stafftools role based on the user's membership in the external_group
        if jit_access || always_on_access
          AssignStafftoolsAccessJob.grant_stafftools_access(user) if user.gh_role != "staff"
          AssignStafftoolsRoleJob.assign_stafftools_role(user, role) if !user.stafftools_roles.pluck(:name).include?(role.name)
        else
          AssignStafftoolsRoleJob.revoke_stafftools_role(user, role) if user.stafftools_roles.pluck(:name).include?(role.name)
        end
      end

      # check for base stafftools role
      %w(access-jit access-always-on).each do |group_name|
        group = ExternalGroup.by_provider(external_provider).where(display_name: "#{stafftools_slug}-stafftools-#{group_name}").first

        # check if the external_group is defined for this tenant, if found return here so
        # revoke_stafftools_access does not get called
        if group&.active_user?(user)
          AssignStafftoolsAccessJob.grant_stafftools_access(user) if user.gh_role != "staff"
          return
        end
      end

      # unassign all of stafftools access if there no stafftools_roles are assigned
      AssignStafftoolsAccessJob.revoke_stafftools_access(user) if user.stafftools_roles.count <= 0
    end

    private

    def find_role_from_okta_group(okta_group)
      proxima_okta_map.find { |o| o["okta_name"] == okta_group }&.fetch("role_name", nil)
    end

    # Compile a list of roles with access to the desired content and action
    def get_access_roles(content_settings, action_name, action_namespace: "name")
      allowed_roles = roles_with_access_for(content_settings)
      roles_with_action_access_for(content_settings, action_name, allowed_roles, action_namespace)
    end

    def get_user_roles(user)
      # "*" signifies access to everyone so add * to the users roles
      user.stafftools_roles.pluck(:name) + ["*"]
    end

    # Return a list of roles permitted to access the content
    def roles_with_access_for(content_settings)
      allowed = []
      if content_settings.length == 0
        # default to open to all users with "*".
        allowed += ["*"]
      else
        allowed += content_settings.first["allowed_roles"]
      end

      allowed
    end

    # Returns a list of roles permitted to access actions within the content
    def roles_with_action_access_for(content_permissions, action_name, allowed_roles, action_namespace)
      # we don't need to check for permissions as there aren't any to check against
      return allowed_roles if content_permissions.empty?
      action_rules = find_action_permissions(content_permissions, action_name, action_namespace)
      # No action roles found, return controller roles
      return allowed_roles if action_rules.empty?
      # This should really live in a linter so that it is done at time of checkin. This
      # is just a sanity check for the time being
      validate_action_rules(action_rules)
      if override_roles = action_rules.first.fetch("allowed_roles_override", false)
        # the action defines new roles, that override the controller level allowed roles
        return override_roles
      elsif excluded_roles = action_rules.first.fetch("excluded_roles", false)
        # we are removing some roles from the controller level allowed roles definitions
        return calculate_excluded_roles(allowed_roles, excluded_roles)
      end

      # No change to the controller setting found
      allowed_roles
    end

    def calculate_excluded_roles(allowed_roles, excluded_roles)
      if allowed_roles.include?("*")
        StafftoolsRole.where("name NOT IN (?)", excluded_roles).pluck(:name)
      else
        allowed_roles - excluded_roles
      end
    end

    # Check rules for validity
    def validate_action_rules(rules)
      rule = rules.first
      if rule.has_key?("allowed_roles")
        raise Stafftools::AccessControl::RuleValidationError.
          new(msg = "invalid action rule #{rule['name']}, cannot set allowed_roles please use allowed_roles_override")
      end

      if rule.has_key?("excluded_roles") && rule.has_key?("allowed_roles_override")
        msg = "Invalid action rule #{rule['name']} cannot set both allowed_roles and excluded_roles"
        raise Stafftools::AccessControl::RuleValidationError.new(msg: msg)
      end
    end

    def find_rest_api_permissions(pattern)
      permissions.fetch("rest_api", []).select do |el|
        el["route_pattern"] == pattern
      end
    end

    def find_controller_permissions(name)
      permissions.fetch("controllers", []).select do |el|
        el["name"] == name
      end
    end

    def find_action_permissions(content_permissions, action_name, action_namespace)
      content_permissions.first.fetch("actions", []).select do |el|
        el[action_namespace] == action_name
      end
    end
  end
end
