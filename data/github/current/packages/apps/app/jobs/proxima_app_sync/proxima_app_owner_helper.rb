# typed: strict
# frozen_string_literal: true

module ProximaAppSync
  module ProximaAppOwnerHelper
    extend T::Helpers

    sig { void }
    def ensure_third_party_apps_owner_exists!
      owner = GitHub.proxima_third_party_apps_owner
      return if owner.present?

      T.bind(self, ApplicationJob)
      with_write do
        Organization.create!(
          login: GitHub.proxima_third_party_apps_owner_login,
          plan: "free",
          organization_billing_email: "ghost-org@github.com",
          admins: [User.create_ghost]
        )
      end
    end

    sig { returns(Integer) }
    def owner_id
      T.bind(self, T.any(CreateAppJobHelper, UpdateAppJobHelper))
      if party_type == ProximaAppHelper::FIRST_PARTY_TYPE
        GitHub.first_party_apps_owner_id
      else
        GitHub.proxima_third_party_apps_owner_id
      end
    end
  end
end
