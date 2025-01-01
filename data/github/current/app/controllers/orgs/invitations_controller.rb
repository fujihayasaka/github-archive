# typed: true
# frozen_string_literal: true

class Orgs::InvitationsController < Orgs::Controller
  include SeatsHelper
  include Orgs::InvitationsControllerMethods
  limit_invitation_roles :admin, :direct_member, :reinstate
  skip_before_action :cap_pagination, unless: :robot?

  before_action :login_required, except: [:show_pending]
  before_action :find_pending_invitation, only: [:accept_pending, :show_pending]
  before_action :organization_admin_required, except: [:accept_pending, :show_pending, :destroy, :reinstate_complete, :reinstate_status, :show_reinstated]
  before_action :sudo_filter, except: %i(
    accept_pending
    create_for_new_org
    destroy
    member_adder_add
    reinstate_complete
    reinstate_status
    show_pending
    show_reinstated
  )

  before_action :ensure_two_factor_requirement_is_met, only: [:accept_pending]

  include Orgs::Invitations::RateLimiting
  setup_org_invite_rate_limiting \
    only: [:create, :create_for_new_org],
    filter: :rate_limiting_enabled?

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show_pending]

  depends_on_clusters ApplicationRecord::Copilot, only: [:show_pending], optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:reinstate_status]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:reinstate_complete]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:show_reinstated]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show_pending, :edit, :reinstate_status],
    optional: true

  def show_pending # rubocop:todo GitHub/UseRestfulActions
    allow_external_redirect_after_post if sso_required_for_joining?
    strip_analytics_query_string
    flash.now[:override_octolytics_location] = true

    if logged_in?
      if this_organization.org_invite_email_verification_enabled? && current_user.spammy?
        flash[:error] = OrganizationInvitation::SPAMMY_INVITEE_ERROR_MESSAGE
      end

      # Check if the email associated with the invite is associated with logged in user
      if pending_invitation.acceptor_needs_to_verify_email?(acceptor: current_user, instrument: true)
        session[:show_email_not_verified_error_message] = true
        session[:url_to_return_to_invite] = request.original_url
        session[:inviting_organization_id] = pending_invitation.organization.id
      elsif this_organization.org_invite_email_verification_enabled?
        session.delete(:show_email_not_verified_error_message)
      end

      # The view prompts the user to enable 2FA and/or SAML SSO if required
      external_identity_session = current_external_identity_session if external_identity_session_fresh?
      view = create_view_model(
        Orgs::Invitations::ShowPendingPageView,
        invitation: pending_invitation,
        invitation_token: params[:invitation_token],
        current_external_identity_session: external_identity_session
      )
      render "orgs/invitations/show_pending", locals: { view: view }
    else
      if GitHub.signup_enabled?
        redirect_to new_nux_signup_path(invitation_token: params[:invitation_token])
      else
        render_sign_up_via_invitation invitation: pending_invitation, invitation_token: params[:invitation_token]
      end
    end
  end

  def accept_pending # rubocop:todo GitHub/UseRestfulActions
    saml_session_owner = this_organization.external_identity_session_owner
    if saml_sso_required?(saml_session_owner)
      render_external_identity_session_required(target: saml_session_owner)
      return
    end

    result = pending_invitation.accept(acceptor: current_user,
                              via_email: params[:via_email].present?)

    # If accepting the invitation fails, redirect and show the error to the user.
    if result.error?
      error = result.error
      if result.status == :does_not_meet_team_requirements
        error = error + "Please contact the person who sent you this invitation."
      end

      flash[:error] = error

      if result.status == :email_not_associated_with_logged_in_user
        return redirect_to settings_email_preferences_path
      end

      return redirect_to org_show_invitation_path
    end

    if ActiveModel::Type::Boolean.new.cast(params[:copilot_seat]).present?
      with_database_error_fallback do
        member_request = MemberFeatureRequest.create(
          requester: current_user,
          request_entity: this_organization,
          feature: MemberFeatureRequest::Feature::CopilotForBusiness
        )
      end
    end

    # Users that needed to verify their email address to accept the invite
    # will have no use for this notice which will show up on their settings/emails page.
    if this_organization.org_invite_email_verification_enabled?
      ActiveRecord::Base.connected_to(role: :writing) do
        current_user.dismiss_notice("show_link_to_org_invite")
      end
    end

    flash[:notice] = case pending_invitation.role
    when "direct_member"
      "You are now a member of #{this_organization.safe_profile_name}!"
    when "admin"
      "You are now an owner of #{this_organization.safe_profile_name}!"
    end

    if params[:return_to].present?
      safe_redirect_to params[:return_to],
                      fallback: user_path(this_organization)
    elsif pending_invitation.reinstate?
      redirect_to org_reinstate_status_path
    else
      redirect_to user_path(this_organization)
    end
  end

  def reinstate_status # rubocop:todo GitHub/UseRestfulActions
    restorable_organization_user = Restorable::OrganizationUser.restorable(this_organization, current_user)
    status = restorable_organization_user.job_status
    if status
      render "orgs/invitations/reinstate_status", locals: {
        organization: this_organization,
        status: status,
        continue_path: reinstate_return_to_path,
      }
    else
      redirect_to user_path(this_organization)
    end
  end

  def show_reinstated # rubocop:todo GitHub/UseRestfulActions
    status = JobStatus.find(params[:status])
    return head 404 unless status

    # Data not processed yet, so keep polling.
    unless status.finished?
      return head 202
    end

    respond_to do |format|
      format.html do
        render partial: "orgs/invitations/show_reinstated", locals: {
            organization: this_organization,
            continue_path: reinstate_return_to_path,
            layout: false,
          }
      end
    end
  end

  # GET: Safely redirects using the `return_to` parameter to prevent attackers
  # injecting malicious URLs into the restore process.
  # If `return_to` is not supplied we redirect to the Organization root path
  def reinstate_complete # rubocop:todo GitHub/UseRestfulActions
    safe_redirect_to reinstate_return_to_path
  end

  def create
    invitee = User.find_by(id: params[:invitee_id])
    return render_404 if invitee&.is_enterprise_managed?


    if invitee.blank? && params[:email].blank?
      return render_404
    end

    team_ids = params[:team_ids] || ""
    team_ids = team_ids.split(",") unless team_ids.is_a?(Array)
    team_ids = team_ids.map(&:to_i).uniq

    inviter = OrganizationInviter.new(
      this_organization,
      actor: current_user,
      role: params[:role],
      invitee: invitee,
      email: params[:email],
      team_ids: team_ids,
    )

    if inviter.invite_user
      notice = "You've invited #{inviter.invitation.email_or_invitee_name} to #{this_organization.safe_profile_name}! They'll be receiving an email shortly."
      if inviter.invitation.email?
        if Rails.env.development?
          # Convenience for developers to see the email invitation accept URL
          # including its hashed token (only visible in this action)
          notice += " #{org_show_invitation_url(this_organization, invitation_token: inviter.invitation.token, via_email: "1")}"
        end
        flash[:notice] = notice
      else
        flash[:notice] = "#{notice} They can also visit #{user_url(this_organization)} to accept the invitation."
      end

      redirect_to org_pending_invitations_path(this_organization, enable_tip: params[:enable_tip].presence)
    else
      flash[:error] = inviter.error
      redirect_to(inviter.return_path)
    end
  rescue OrganizationInviter::RequiresVerification
    render_email_verification_required
  end

  def create_for_new_org # rubocop:todo GitHub/UseRestfulActions
    result = invite_member(params[:member])
    case result
    when :email_verification_required
      render status: 403, json: {
        message_html: render_to_string(
          partial: "orgs/invitations/email_verification_required_message",
        ),
      }
    when OrganizationInvitation::NoAvailableSeatsError
      head 400
    when ::OrganizationInvitation::TradeControlsError
      render_trade_restricted_invitee
    when OrganizationInvitation::AlreadyAcceptedError, OrganizationInvitation::InvalidError,
           ActiveRecord::RecordInvalid
      render_404
    else
      invitation, invitee = result
      render json: {
        filled_seats_percent: this_organization.filled_seats_percent,
        selectors: {
          ".unstyled-total-seats" => this_organization.seats,
          ".unstyled-filled-seats" => this_organization.filled_seats,
        },
        list_item_html: render_to_string(partial: "orgs/invitations/invitation_for_new_org",
          locals: {
            user: invitee,
            invitation: invitation,
          },
        ),
      }
    end
  end

  def destroy
    invitation = this_organization.pending_invitations.find(params[:organization_invitation_id])
    return render_404 unless invitation.cancelable_by?(current_user)

    invitation.cancel(actor: current_user)

    if request.xhr?
      render json: {
        filled_seats_percent: this_organization.filled_seats_percent,
        selectors: {
          ".unstyled-total-seats" => this_organization.seats,
          ".unstyled-filled-seats" => this_organization.filled_seats,
        },
      }
    elsif invitation.invitee == current_user || invitation.actor_can_cancel_email_invite?(actor: current_user)
      flash[:notice] = "You've canceled your invitation to #{this_organization.safe_profile_name}."
      redirect_to "/"
    else
      flash[:notice] = "You've canceled #{invitation.email_or_invitee_name}'s invitation to #{this_organization.safe_profile_name}."
      safe_redirect_to params[:return_to], fallback: org_pending_invitations_path(this_organization)
    end
  end

  def edit
    invitee = User.find_by_login(params[:invitee_login])
    if invitee.present? && invitee_invalid_and_hidden_from_public?(invitee)
      return render_404
    end

    strip_analytics_query_string
    flash.now[:override_octolytics_location] = true
    invitation_request = OrganizationInvitationRequest.new(
      email: params[:email],
      login: params[:invitee_login],
      organization: this_organization,
      current_user: current_user,
      start_fresh: params[:start_fresh],
    )

    if invitation_request.invalid?
      render "orgs/invitations/uninvitable", locals: {
        organization: invitation_request.organization,
        invitee: invitation_request.invitee,
        existing_invitation: invitation_request.invitation,
        status: invitation_request.invitation_status,
        restorable_organization_user: invitation_request.restorable_organization_user
      }
    elsif invitation_request.reinstating_membership?
      view = create_view_model(
        Orgs::Invitations::ReinstateView.select_view(invitation_request.invitation, this_organization.enterprise_managed_user_enabled?),
        invitation_request.to_h
      )
      render "orgs/invitations/reinstate", locals: { view: view }
    else
      invite_h = invitation_request.to_h
      team_ids = params[:team_ids] || []
      role = params[:role] || "direct_member"

      existing = invite_h[:existing_invitation]
      if existing
        # do not re-add the invitation's team ids if we are paging through
        # otherwise you can override any deselection of the original teams
        unless request.query_parameters.has_key?(:team_ids)
          if existing.teams
            team_ids = team_ids + existing.teams.pluck(:id).map(&:to_s)
          end

          selected_team = params[:team]
          if selected_team
            team = Team.with_org_name_and_slug(this_organization.login, selected_team) # rubocop:disable GitHub/DoNotAllowLogin login used in a query
            team_ids.push(team.id) if team
          end
        end

        # do not update the role if we are paging through
        # otherwise we can override the user selected role
        unless request.query_parameters.has_key?(:role)
          role = existing.role if existing.role
        end
      end

      view = create_view_model(Orgs::Invitations::EditPageView, invite_h.merge(
        selected_team: params[:team], start_fresh: params[:start_fresh], page: params[:page], team_ids: team_ids, role: role, query: params[:query]
      ))

      if request.xhr?
        respond_to do |format|
          format.html do
            render partial: "orgs/invitations/teams/list", locals: { view: view }
          end
        end
      else
        render "orgs/invitations/edit", locals: { view: view }
      end
    end
  end

  def member_adder_add # rubocop:todo GitHub/UseRestfulActions
    identifier = (params[:identifier] ||= "").strip

    return render_404 unless identifier.present?

    if User.valid_email?(identifier)
      redirect_to org_edit_email_invitation_path(this_organization, email: identifier, enable_tip: params[:enable_tip].presence)
    else
      redirect_to org_edit_invitation_path(this_organization, identifier, enable_tip: params[:enable_tip].presence)
    end
  end

  def update
    invitee = params[:email] || User.find_by_login(params[:invitee_login])
    invitation = if invitee.is_a?(String)
      this_organization.pending_invitation_for(email: invitee)
    else
      this_organization.pending_invitation_for(invitee)
    end

    return render_404 if invitation.nil?
    return render_404 if invitation&.invitee&.is_enterprise_managed?

    # After a change in how invites work for trade restricted users this will only
    # return true for fully trade restricted organizations. This can likely be removed!
    if invitation.prevented_by_trade_controls_restrictions?
      flash[:error] = TradeControls::Notices.notice_as_plaintext(:org_invite_restricted)
      return redirect_to :back
    end

    if OrganizationInvitation.valid_role?(params[:role])
      previous_role = invitation.role
      updated_role = params[:role]
      if previous_role == updated_role
        GitHub.dogstats.increment("organization_invitation", tags: ["action:update"])
      elsif previous_role == "reinstate"
        GitHub.dogstats.increment("organization_invitation", tags: ["action:convert_to_invite"])
      elsif updated_role == "reinstate"
        GitHub.dogstats.increment("organization_invitation", tags: ["action:convert_to_reinstate"])
      end
      invitation.role = params[:role]
      invitation.save
    end

    unless params[:role].to_sym == :reinstate
      team_ids = params[:team_ids] || ""
      team_ids = team_ids.split(",") unless team_ids.is_a?(Array)
      team_ids = team_ids.map(&:to_i).uniq
      teams = this_organization.teams.where(id: team_ids).distinct

      teams_to_remove = invitation.teams - teams
      teams_to_remove.each { |team| invitation.remove_team(team) }

      teams_to_add = teams - invitation.teams
      teams_to_add.each { |team| invitation.add_team(team, inviter: current_user) }
    end

    flash[:notice] = "You've successfully updated #{invitation.email_or_invitee_name}'s invitation."

    redirect_to org_pending_invitations_path(this_organization)
  end

  private

  # Filter used with `setup_org_invite_rate_limiting`
  def rate_limiting_enabled?
    !GitHub.bypass_org_invites_enabled?
  end

  def email_verification_required?
    current_user.requires_verification_to_invite_by_email?
  end

  def saml_sso_required?(saml_session_owner)
    !saml_requirement_met?(saml_session_owner) || external_identity_with_saml?(saml_session_owner)

  end

  def saml_requirement_met?(saml_session_owner)
    saml_session_owner.saml_sso_requirement_met_by?(current_user) ||
      pending_invitation.reinstating_outside_collaborator?
  end

  def external_identity_with_saml?(saml_session_owner)
    pending_invitation.external_identity.present? &&
      saml_session_owner.saml_provider.saml_provisioning_enabled?
  end

  def org_invite_rate_limited
    org_invite_rate_limit_policy.record_rate_limited(action_name, controller_name)

    case action_name
    when "create"
      render "orgs/invitations/rate_limited", status: 429, locals: {
        organization: this_organization,
      }
    when "create_for_new_org"
      render status: 429, json: {
        message_html: render_to_string(
          partial: "orgs/invitations/rate_limited_message",
          formats: [:html],
        ),
      }
    end
  end

  def ensure_two_factor_requirement_is_met
    unless this_organization.two_factor_requirement_met_by?(current_user)
      redirect_to org_show_invitation_path
    end
  end

  def reinstate_return_to_path
    params.fetch(:return_to, user_path(this_organization))
  end

  def organization_is_on_free_plan?
    this_organization.uncharged_account?
  end

  def render_trade_restricted_invitee
    render status: 403, json: {
      message_html: render_to_string(
        partial: "orgs/invitations/invitee_trade_restricted",
        formats: [:html],
      ),
    }
  end

  def invite_member(member)
    if User.valid_email?(member)
      return :email_verification_required if email_verification_required?
      email = member
    else
      invitee = User.find_by_login(member)
    end

    return false unless invitee || email

    begin
      invitation = this_organization.invite(invitee, email: email, inviter: current_user, role: :direct_member, invitation_source: :member)
      [invitation, invitee]
    rescue OrganizationInvitation::NoAvailableSeatsError, ::OrganizationInvitation::TradeControlsError,
           OrganizationInvitation::AlreadyAcceptedError, OrganizationInvitation::InvalidError,
           ActiveRecord::RecordInvalid => ex
      ex
    end
  end

  # Private: Determine if the invitee is invalid and hidden from the public. Since an invitee is of
  # type User, an attempt can be made to replace the invitee with other type User objects that are
  # hidden from the public during the invitation flow. While such an attempt won't succeed,
  # returning a descriptive error message would disclose their existence. This method is used to
  # determine such invalid and hidden invitees, to prevent the disclosure of their existence.
  #
  # invitee - The User being invited.
  #
  # Returns a Boolean.
  def invitee_invalid_and_hidden_from_public?(invitee)
    # Don't permit viewing EMU users in organizations not owned by the associated EMU enterprise.
    return true if invitee.is_enterprise_managed? && invitee.enterprise_managed_business.present? &&
      invitee.enterprise_managed_business != this_organization.business
    # Don't permit viewing EMU organizations.
    return true if invitee.is_a?(Organization) && invitee.enterprise_managed_user_enabled?
    # Don't permit viewing mannequins.
    return true if invitee.mannequin?
    false
  end
end
