# typed: strict
# frozen_string_literal: true

module CustomProperties
  PropertySource = T.type_alias { T.any(::Organization, ::Business) }
  PropertyValue = T.type_alias { T.any(String, T::Array[String]) }

  AuthzdActor = T.type_alias do
    T.any(
      User,
      OrganizationProgrammaticAccessGrant,
      UserProgrammaticAccessGrant,
      IntegrationInstallation,
      ScopedIntegrationInstallation,
      SiteScopedIntegrationInstallation)
  end

  class UserEditPermissions < T::Struct
    # If true, a user has the org-level FGP and can edit properties for all repos in the org
    const :org, T::Boolean

    # If true, a user has the repo-level FGP and can edit properties for this repo
    const :repo, T::Boolean
  end
end
