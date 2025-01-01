# typed: true
# frozen_string_literal: true

class Api::ActionsVerifiedOwners < Api::App
  MAX_LOGINS = 1_000
  TOO_MANY_LOGINS_MSG = "Too many logins. Please supply up to #{MAX_LOGINS} logins."

  # This returns the verified owners from given owners
  post "/marketplace/actions/verified_owners", operation_id: :internal do
    @route_owner = "@github/c2c-actions-experience"

    # CAP is okay to bypass here: see https://github.com/github/github/pull/173799
    control_access :check_verified_owners,
      resource: current_integration,
      allow_integrations: true,
      allow_user_via_granular_actor: false,
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    deliver_error!(404) unless GitHub.actions_enabled?
    deliver_error!(404) unless connect_request?

    logins = receive(Hash).fetch("logins", []).uniq

    if logins.count > MAX_LOGINS
      deliver_error!(422, message: TOO_MANY_LOGINS_MSG)
    end

    orgs = Organization.select(:id, :login).where(login: logins)
    verified_org_ids = Configurable::RepositoryActionVerifiedOrg.filter_verified_org_ids(orgs.pluck(:id)).to_set
    # Actions team will communicate any change in requirements to disambiguate display and unique in future.
    verified_logins = orgs.select { |org| verified_org_ids.include?(org.id) }.map { |org| org.login.downcase } # rubocop:disable GitHub/DoNotAllowLogin

    deliver_raw({ verified_logins: verified_logins }, status: 200)
  end
end
