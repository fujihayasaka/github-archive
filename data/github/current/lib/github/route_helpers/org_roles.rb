# typed: true
# frozen_string_literal: true

module GitHub
  module RouteHelpers
    # Controllers:
    # - businesses/org_roles#create
    # - orgs/org_roles#create
    # Paths:
    # - POST /enterprises/:slug/org_roles
    # - POST /organizations/:organization_id/settings/org_roles
    def gh_create_org_role_path(owner)
      if owner.is_a?(Business)
        Rails.application.routes.url_helpers.enterprise_create_organization_role_path(owner)
      else
        Rails.application.routes.url_helpers.settings_org_roles_path(owner)
      end
    end

    # Controllers:
    # - businesses/org_roles#update
    # - orgs/org_roles#update
    # Paths:
    # - PUT /enterprises/:slug/org_roles/:id
    # - PUT /organizations/:organization_id/settings/org_roles/:id/update
    def gh_update_org_role_path(owner, role)
      if owner.is_a?(Business)
        Rails.application.routes.url_helpers.enterprise_update_organization_role_path(owner, role)
      else
        Rails.application.routes.url_helpers.update_settings_org_roles_path(owner, role)
      end
    end
  end
end
