# typed: strict
# frozen_string_literal: true

module Business::RolesAndPermissionsDependency
  extend T::Helpers

  requires_ancestor { Business }

  # Public: This checks if the business supports custom organization roles
  sig { returns(T::Boolean) }
  def custom_organization_roles_supported?
    return false unless plan_supports?(:custom_roles)

    erp_feature_enabled?(:enterprise_custom_organization_roles)
  end

  sig { returns(T::Boolean) }
  def custom_enterprise_roles_supported?
    return false unless plan_supports?(:custom_roles)

    erp_feature_enabled?(:custom_enterprise_role_feature)
  end

  sig { returns(T::Boolean) }
  def enterprise_teams_org_roles_supported?
    erp_feature_enabled?(:enterprise_teams_org_roles)
  end

  sig { params(feature: Symbol).returns(T::Boolean) }
  def erp_feature_enabled?(feature)
    # feature flag in development
    return true if feature_enabled?(feature)

    # feature is staffshipped for this account
    return true if feature_enabled?("erp_staffship_#{feature}") && feature_enabled?(:erp_staffship)

    # feature is released to private preview
    feature_enabled?("erp_preview_#{feature}") && feature_enabled?(:erp_preview)
  end
end
