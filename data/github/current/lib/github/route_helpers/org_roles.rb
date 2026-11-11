# typed: true
# frozen_string_literal: true

module GitHub
  module RouteHelpers
    # Controllers:
    # - business/org_roles#org_roles_fgp_metadata
    # - orgs/org_roles#fgp_metadata
    # Paths:
    # - GET /enterprises/:slug/org_roles/fgp_metadata
    # - GET /organizations/:organization_id/settings/org_roles/new/fgp_metadata
    def gh_org_roles_fgp_metadata_path(owner)
      if owner.is_a?(Business)
        # The `Rails.application.routes.url_helpers.` is for Sorbet
        Rails.application.routes.url_helpers.enterprise_org_roles_fgp_metadata_path(owner)
      else
        Rails.application.routes.url_helpers.settings_org_roles_fgp_metadata_path(owner)
      end
    end

    # Controllers:
    # - businesses/org_roles#repo_roles_fgp_metadata
    # - orgs/roles#fgp_metadata
    # Paths:
    # - GET /enterprises/:slug/repo_roles/fgp_metadata
    # - GET /organizations/:organization_id/settings/roles/new/fgp_metadata
    def gh_repo_roles_fgp_metadata_path(owner)
      if owner.is_a?(Business)
        Rails.application.routes.url_helpers.enterprise_repo_roles_fgp_metadata_path(owner)
      else
        Rails.application.routes.url_helpers.autocomplete_repository_permissions_path(owner)
      end
    end

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
