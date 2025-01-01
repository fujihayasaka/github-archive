# typed: strict
# frozen_string_literal: true

module CustomProperties
  PropertySource = T.type_alias { T.any(::Organization, ::Business) }
  IPropertySource = T.type_alias { T.any(Orgs::IOrganization, Admin::IBusiness) }
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
end
