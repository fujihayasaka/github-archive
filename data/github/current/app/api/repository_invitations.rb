# typed: true
# frozen_string_literal: true

class Api::RepositoryInvitations < Api::App
  include ReceiveSchemaWithOpenApi

  # List the open repository invitations for a repository
  get "/repositories/:repository_id/invitations", operation_id: "repos/list-invitations" do
    repo = find_repo!
    control_access :list_repository_invitations,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: forbids_when_user_has_limited_repo_access?(repo)

    invitations = repo.repository_invitations.
    includes(:repository).
    preload([:invitee, :inviter, :role])

    deliver(:fgp_repository_invitation_hash, paginate_rel(invitations))
  end

  # Rescind a specific repository invitation
  delete "/repositories/:repository_id/invitations/:invitation_id", operation_id: "repos/delete-invitation" do
    # Introducing strict validation of the repository-invitation.rescind
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("repository-invitation", "rescind", skip_validation: true)

    repo = find_repo!
    control_access :admin_repository_invitations,
      resource: repo,
      forbid: forbids_when_user_has_limited_repo_access?(repo),
      allow_integrations: true,
      allow_user_via_granular_actor: true

    invitation = scope_invitation_by_repo(repo, params[:invitation_id])
    invitation.destroy
    deliver_empty(status: 204)
  end

  # Modify the permissions on an outstanding repository invitation
  patch "/repositories/:repository_id/invitations/:invitation_id", operation_id: "repos/update-invitation" do
    repo = find_repo!
    control_access :admin_repository_invitations,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: forbids_when_user_has_limited_repo_access?(repo)

    data = receive_with_schema("fgp-repository-invitation", "update-legacy")

    invitation = scope_invitation_by_repo(repo, params[:invitation_id])
    invitation.set_permissions(data["permissions"], current_user)
    deliver_error(422, errors: invitation.errors) unless invitation.save

    deliver(:fgp_repository_invitation_hash, invitation)

  rescue ArgumentError => e
    deliver_error(422, errors: e.message)
  end

  # List open repository invitations for user
  get "/user/repository_invitations", operation_id: "repos/list-invitations-for-authenticated-user" do
    control_access :read_user_public_repository_invitations,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: true,
      challenge: true

    invitations = current_user.received_repository_invitations.
      includes(:repository).
      preload([:invitee, :inviter, :role])

    if current_user.using_auth_via_integration?
      invitations = Platform::Security::RepositoryAccess.with_viewer(current_user) do
        permission = Platform::Authorization::Permission.new(viewer: current_user, integration: current_integration, origin: Platform::ORIGIN_API)
        permission.filter_permissible_repository_resources(current_user, invitations, resource: "administration")
      end
    else
      unless access_allowed?(:read_user_private_repository_invitations, resource: current_user, allow_integrations: false, allow_user_via_granular_actor: true)
        invitations = invitations.includes(:repository).where("repositories.public = ?", true).references(:repository)
      end
    end

    deliver(:fgp_repository_invitation_hash, paginate_rel(invitations))
  end

  # Accept a specific repository invitation
  patch "/user/repository_invitations/:invitation_id", operation_id: "repos/accept-invitation-for-authenticated-user" do
    receive_with_schema("repository-invitation", "accept")

    invitation = scope_invitation_by_user(params[:invitation_id])

    ensure_repository_for_invitation!(invitation)
    repository = invitation.repository

    control_access :accept_or_decline_repo_invitation,
      resource: invitation,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    unless repository.two_factor_requirement_met_by?(current_user)
      deliver_error!(
        403,
        message: "The #{repository.owner.safe_profile_name} organization requires all members to have two-factor authentication enabled.",
        documentation_url: "/v3/orgs/members/#edit-your-organization-membership",
      )
    end

    if repository.trade_restricted?
      deliver_error!(
        changeset_active?(:change_accept_repository_invitation_response_status) ? 451 : 403,
        message: TradeControls::Notices.notice_as_plaintext(:api_access_restricted),
      )
    end

    invitation.accept!
    deliver_empty(status: 204)
  rescue ::Permissions::Participant::PermissionGrantError => e
    deliver_error(422, errors: e.message)
  end

  # Decline a specific repository invitation
  delete "/user/repository_invitations/:invitation_id", operation_id: "repos/decline-invitation-for-authenticated-user" do
    receive_with_schema("repository-invitation", "decline")

    invitation = scope_invitation_by_user(params[:invitation_id])

    ensure_repository_for_invitation!(invitation)
    control_access :accept_or_decline_repo_invitation,
      resource: invitation,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    invitation.reject!
    deliver_empty(status: 204)
  end

  private

  def ensure_repository_for_invitation!(invitation)
    return true if invitation.repository.present?

    invitation.destroy
    deliver_error!(409, message: "The repository for this invitation has been deleted.")
  end

  def forbids_when_user_has_limited_repo_access?(repo)
    return true if repo.public?
    return true if access_allowed?(:get_repo,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
    )

    false
  end

  def scope_invitation_by_user(invitation_id)
    deliver_error!(404) unless logged_in?
    record_or_404(current_user.received_repository_invitations.find_by_id(invitation_id))
  end

  def scope_invitation_by_repo(repo, invitation_id)
    record_or_404(repo.repository_invitations.find_by_id(invitation_id))
  end
end
