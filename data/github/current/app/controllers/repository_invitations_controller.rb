# typed: false
# frozen_string_literal: true

class RepositoryInvitationsController < AbstractRepositoryController

  skip_before_action :privacy_check, only: [:show]
  skip_before_action :authorization_required

  javascript_bundle :signup

  before_action :login_required, except: [:show]
  before_action :find_pending_invitation, only: [:show]
  before_action :scope_invitation, except: [:destroy, :show]
  before_action :sudo_filter, only: [:set_permissions]
  before_action :invitee_is_current_user, only: [:accept, :reject, :block_inviter]
  before_action :ensure_two_factor_requirement_is_met, only: [:accept]
  skip_before_action :network_privilege_check, only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
  def current_business # rubocop:todo GitHub/UseRestfulActions
    @_business ||= current_repository&.organization&.business
  end
  # rubocop:enable GitHub/ControllersShouldUseMemoizeForMemoization
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  def destroy
    member = params[:member]
    if User.valid_email?(member)
      invitation = RepositoryInvitation.find_by(email: member, repository_id: current_repository.id)
    else
      invitee = User.find_by_login(member)
      invitation = RepositoryInvitation.find_by(invitee_id: invitee&.id, repository_id: current_repository.id)
    end

    if invitation
      member_label = invitation.email_or_invitee_login
      if invitation.cancel!(actor: current_user)
        flash[:notice] = "#{member_label} is no longer invited to this repository."
        redirect_to repository_access_management_path(user_id: current_repository.owner.display_login, repository: current_repository.name)
      else
        respond_to do |wants|
          wants.html { redirect_to repository_access_management_path(user_id: current_repository.owner.display_login, repository: current_repository.name) }
          wants.json { render json: { error: "You are not authorized to delete an invitation." } }
        end
      end
    else
      respond_to do |wants|
        wants.html { redirect_to repository_access_management_path(user_id: current_repository.owner.display_login, repository: current_repository.name) }
        wants.json { render json: { error: "Invitation for user not found." } }
      end
    end
  end

  def show
    render_404 and return unless current_repository

    if logged_in?
      if pending_invitation.repository.private? &&  pending_invitation.invitee&.has_any_trade_restrictions?
        flash[:trade_controls_user_billing_error] = true
      end
      view = create_view_model(RepositoryInvitations::ShowView, invitation: pending_invitation)
      render "repository_invitations/show", locals: { view: view }
    else
      if GitHub.signup_enabled?
        redirect_to new_nux_signup_path(repo_invitation_token: params[:invitation_token])
      else
        render_sign_up_via_repo_invitation(invitation: pending_invitation, invitation_token: params[:invitation_token])
      end
    end
  end

  def accept # rubocop:todo GitHub/UseRestfulActions
    if repo_invitation.accept!(acceptor: current_user)
      flash[:notice] = "You now have #{permission_string} access to the #{repo_invitation.repository.name_with_display_owner} repository."
      redirect_to repo_invitation.repository
    else

      repo = repo_invitation.repository
      if repo.trade_restricted?
        flash[:error] = TradeControls::Notices.notice_as_plaintext(:org_invite_restricted)
      elsif repo_invitation.invite_expired?
        # Add extra check to display the specific expired invite error
        flash[:error] = "This invitation has expired."
      else
        flash[:error] = "This invitation is invalid."
      end

      redirect_to current_user
    end
  rescue ::Permissions::Participant::PermissionGrantError => e
    flash[:error] = e.message
    redirect_to repo_invitation.repository
  end

  def reject # rubocop:todo GitHub/UseRestfulActions
    repo_invitation.reject!
    flash[:notice] = "You have declined the invitation to the #{repo_invitation.repository.name_with_display_owner} repository."
    redirect_to current_user
  end

  def set_permissions # rubocop:todo GitHub/UseRestfulActions
    repo_invitation.set_permissions(params[:permission], current_user)
    head 200
  rescue RepositoryInvitation::InsufficientAbilities
    head 403
  end

  def permission_string # rubocop:todo GitHub/UseRestfulActions
    case repo_invitation.permission_string
    when "read"
      "view"
    when "triage"
      "triage"
    when "write"
      "push"
    when "maintain"
      "maintain"
    when "admin"
      "admin"
    else
      ""
    end
  end

  def block_inviter # rubocop:todo GitHub/UseRestfulActions
    repo_invitation.reject!
    current_user.block(repo_invitation.inviter)
    flash[:notice] = "You have blocked #{repo_invitation.inviter.display_login}."
    redirect_to settings_blocked_users_path
  end

  private

  def invitee_is_current_user
    return render_404 unless repo_invitation
    return render_404 unless logged_in?

    # email invitations can be accepted by any user that received
    # the link with the correct token
    if repo_invitation.email?
      token = RepositoryInvitation.digest_token(params[:invitation_token])
      return render_404 unless token.present?

      render_404 unless SecurityUtils.secure_compare(repo_invitation.hashed_token, token)
    else
      render_404 unless repo_invitation.invitee == current_user
    end
  end

  def scope_invitation
    unless repo_invitation
      if current_repository
        redirect_to current_repository
      else
        redirect_to current_user
      end
    end
  end

  def repo_invitation # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @invitation ||= RepositoryInvitation.find_by_id(params[:invitation_id])
  end

  def add_member(member)
    result = RepositoryInvitation.invite_to_repo(
      member,
      current_user,
      current_repository
    )
    if result[:success]
      if current_repository.member?(member)
        direct_access_list = ::RepositoryAccessList.new(repository: current_repository, current_user:)

        repository_roles = ::RepositoryMemberRoles.fetch(
          repository:   current_repository,
          current_user: current_user,
          members:      direct_access_list.user_results,
          teams:        direct_access_list.repository_teams,
        )

        result[:html] = render_to_string(
          partial: "edit_repositories/admin_screen/access_management/member",
          formats: :html,
          locals: {
            member: member,
            view: create_view_model(
              EditRepositories::Pages::ManagedAccessPageView,
              repository: current_repository,
              current_user:,
              repository_roles:,
              direct_access_list:
            )
          }
        )
      else
        result[:html] = render_to_string(
          partial: "edit_repositories/admin_screen/access_management/invitation",
          formats: :html,
          locals: {
            invitee:    result[:invitation].invitee,
            invitation: result[:invitation],
            view:       create_view_model(EditRepositories::Pages::ManagedAccessPageView.new(repository: current_repository, current_user: current_user))
          }
        )
      end
    end
    result
  end

  def handle_member_not_found
    respond_to do |wants|
      wants.html do
        flash[:error] = "User not found"
        redirect_to(edit_repository_path(current_repository))
      end
      wants.json do
        render json: { error: "User not found" }
      end
    end
  end

  def ensure_two_factor_requirement_is_met
    if !repo_invitation.repository.two_factor_requirement_met_by?(current_user)
      redirect_to repository_invitation_path(repo_invitation.invitee, repo_invitation.repository)
    end
  end

  def resource_for_conditional_access
    return self unless repo_invitation
    repo_invitation
  end

  def target_for_conditional_access
    # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    return :no_target_for_conditional_access unless owner
    owner
  end

  def find_pending_invitation
    @pending_invitation ||= if email_repo_invitation?
      find_email_invitation
    elsif logged_in?
      find_user_invitation
    end

    @pending_invitation || pending_invitation_not_found
  end
  attr_reader :pending_invitation

  def find_email_invitation
    return unless email_repo_invitation?
    current_repository.repository_invitations.find_by_token(params[:invitation_token])
  end

  def find_user_invitation
    current_user.received_repository_invitations.find_by_repository_id(current_repository.id)
  end

  def pending_invitation_not_found
    if login_required_to_view_invitation?
      login_required
    elsif current_repository.adminable_by?(current_user)
      flash[:notice] = "Repository invitation URLs work for invited users only. You may only share this URL with an invited user."
      redirect_to repository_access_management_path(current_repository.owner, current_repository), status: 301
    elsif current_repository.all_members.include?(current_user)
      redirect_to current_repository, status: 301
    else
      if current_repository.private?
        render_404
      else
        flash[:error] = "Sorry, we couldn't find that repository invitation. It is possible that the invitation was revoked or that you are not logged into the invited account."
        render html: "", layout: true
      end
    end
  end

  def login_required_to_view_invitation?
    !logged_in? && !email_repo_invitation?
  end

  def email_repo_invitation?
    params[:invitation_token].present?
  end

  def render_sign_up_via_repo_invitation(invitation:, invitation_token: nil)
    render "repository_invitations/sign_up_via_repo_invitation",
      locals: { invitation: invitation, invitation_token: invitation_token },
      layout: "layouts/session_authentication"
  end

  def route_supports_advisory_workspaces?
    case action_name
    when "show", "accept", "reject"
      true
    else
      false
    end
  end
end
