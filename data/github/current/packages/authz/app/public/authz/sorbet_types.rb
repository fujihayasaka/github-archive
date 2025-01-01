# typed: strict
# frozen_string_literal: true

module Authz
  module SorbetTypes
    ProgrammaticActor = T.type_alias do
      T.any(
        OrganizationProgrammaticAccessGrant,
        UserProgrammaticAccessGrant,
        IntegrationInstallation,
        ScopedIntegrationInstallation,
        SiteScopedIntegrationInstallation,
        GlobalIntegrationInstallation
      )
    end

    Actor = T.type_alias do
      T.any(
        User,
        ProgrammaticActor
      )
    end

    Subject = T.type_alias do
      T.any(
        Organization,
        Business
      )
    end
  end
end
