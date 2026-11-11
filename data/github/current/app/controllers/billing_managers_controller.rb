# typed: strict
# frozen_string_literal: true

class BillingManagersController < ApplicationController

  include OrganizationsHelper
  include Orgs::InvitationsControllerMethods

  limit_invitation_roles :billing_manager

  # Always render a 404 when billing is disabled.
  # See ApplicationController#ensure_billing_enabled.
  before_action :ensure_billing_enabled

  before_action :login_required, except: [:show_pending, :sign_up]
  before_action :this_organization_required
  before_action :find_pending_invitation, only: [:show_pending, :accept, :sign_up]
  before_action :check_ofac_flagged_user, only: [:show_pending, :accept]
  before_action :org_billing_management_only, except: [:show_pending, :accept, :sign_up]
  before_action :ensure_two_factor_requirement_is_met, only: [:accept]
  before_action :sudo_filter, only: [:create]

  include Orgs::Invitations::RateLimiting
  setup_org_invite_rate_limiting only: [:create]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    only: [:show_pending]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    only: [:sign_up]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    only: [:invitee_suggestions]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show_pending], optional: true

  sig { void }
  def new
    return render_404 if this_organization.business.present? && !this_organization.sponsors_invoiced?
    respond_to do |format|
      format.html do
        view = create_view_model(BillingManagers::NewView,
          organization: this_organization,
          rate_limited: at_rate_limit?(action: :create, stealthy: true),
        )
        render "billing_managers/new", locals: { view: view }
      end
    end
  end

  sig { void }
  def show_pending # rubocop:todo GitHub/UseRestfulActions
    if this_organization.org_invite_email_verification_enabled?
      if logged_in?
        if current_user.spammy?
          flash[:error] = OrganizationInvitation::SPAMMY_INVITEE_ERROR_MESSAGE
        end

        # Method below duplicates call to check if FF is enabled, but this won't be the case when we remove the FF
        # call to check if FF is enabled is memoized
        if pending_invitation.acceptor_needs_to_verify_email?(acceptor: current_user, instrument: true)
          session[:show_email_not_verified_error_message] = true
          session[:url_to_return_to_invite] = request.original_url
          session[:inviting_organization_id] = pending_invitation.organization.id
        else
          session.delete(:show_email_not_verified_error_message)
        end
      else
        return sign_up
      end
    end

    respond_to do |format|
      format.html do
        view = create_view_model(BillingManagers::ShowPendingView, invitation: pending_invitation)
        render "billing_managers/show_pending", locals: { view: view }
      end
    end
  end

  sig { void }
  def accept # rubocop:todo GitHub/UseRestfulActions
    result = pending_invitation.accept(acceptor: current_user, via_email: params[:via_email].present?)

    if result.success?
      # Users that needed to verify their email address to accept the invite
      # will have no use for this notice which shows up on their settings/emails page.
      if this_organization.org_invite_email_verification_enabled?
        ActiveRecord::Base.connected_to(role: :writing) do
          current_user.dismiss_notice("show_link_to_org_invite")
        end
      end

      flash[:notice] = "You are now a billing manager of #{this_organization.safe_profile_name}!"
      redirect_to settings_org_billing_path(this_organization)
    else
      flash[:error] = result.error
      # prompt user to add/verify the email address associated with the email invite if they haven't
      if result.status == :email_not_associated_with_logged_in_user
        return redirect_to settings_email_preferences_path
      end
      redirect_to org_show_pending_billing_manager_invitation_path(this_organization)
    end
  end

  sig { void }
  def sign_up # rubocop:todo GitHub/UseRestfulActions
    render_sign_up_via_invitation invitation: pending_invitation, billing_manager_invite: true
  end

  sig { void }
  def cancel # rubocop:todo GitHub/UseRestfulActions
    if User.valid_email?(params[:id])
      email = params[:id]
    else
      user = User.find_by!(login: params[:id])
    end

    invitation = this_organization.pending_invitation_for(user, email: email, role: :billing_manager)
    return render_404 unless invitation

    invitation.cancel(actor: current_user)
    flash[:notice] = "Successfully canceled the invitation."
    redirect_to settings_org_billing_path(this_organization)
  end

  sig { void }
  def destroy
    user = User.find_by!(login: params[:id])
    current_organization_for_member_or_billing.billing.remove_manager(user, actor: current_user)
    flash[:notice] = "Successfully removed billing management access for @#{user.display_login}."
    if current_organization_for_member_or_billing.billing_manager?(current_user) || current_organization_for_member_or_billing.adminable_by?(current_user)
      redirect_to settings_org_billing_path(current_organization_for_member_or_billing)
    else
      redirect_to dashboard_path
    end
  end

  sig { void }
  def invitee_suggestions # rubocop:todo GitHub/UseRestfulActions
    headers["Cache-Control"] = "no-cache, no-store"

    respond_to do |format|
      format.html_fragment do
        render partial: "billing_managers/invitee_suggestions", formats: :html, locals: {
          view: create_view_model(BillingManagers::InviteeSuggestionsView,
            organization: this_organization,
            query: params[:q]
          )
        }
      end
    end
  end

  sig { void }
  def create
    if User.valid_email?(params[:id])
      email = params[:id]

      if email_verification_required?
        # Require verified email address to send invites to email addresses
        return render_email_verification_required
      end
    else
      user = User.find_by(login: params[:id])
    end

    if !invitable?(user) && email.nil?
      flash[:error] = if params[:id].match(User::LOGIN_REGEX)
        "We couldn’t find a user named @#{params[:id]}. Please enter the GitHub username of the person you want to invite."
      else
        "We couldn’t find a user with the username you provided. Please enter the GitHub username of the person you want to invite."
      end
      redirect_to :back
    else
      if user&.has_any_trade_restrictions? || this_organization.has_any_trade_restrictions?
        flash[:error] = "The user cannot be added as a billing manager of the organization."
        return redirect_back(fallback_location: settings_org_billing_path(current_organization_for_member_or_billing))
      end

      if user == current_user
        # Add yourself directly as a billing manager
        current_organization_for_member_or_billing.billing.add_manager(current_user, actor: current_user)
        invitation = current_organization_for_member_or_billing.pending_invitation_for(current_user, role: :billing_manager)
        invitation.cancel(actor: current_user) if invitation
        flash[:notice] = "You are now a billing manager for #{current_organization_for_member_or_billing.safe_profile_name}."
      else
        # Otherwise create a normal invitation
        errors = []
        begin
          invitation = current_organization_for_member_or_billing.invite(user, email: email, inviter: current_user, role: :billing_manager, invitation_source: :member)
          GitHub.dogstats.increment("billing.managers.invite.count")
        rescue OrganizationInvitation::AlreadyAcceptedError, OrganizationInvitation::InvalidError, ActiveRecord::RecordInvalid => error
          errors << error.message
        end

        if errors.any?
          flash[:error] = errors.first
        else
          flash[:notice] = "Successfully invited #{invitation.email_or_invitee_name} to be a billing manager. They’ll be receiving an email shortly."

          # Show the email invite link to the inviter if in development, so it can be followed
          if Rails.env.development? && invitation.email?
            flash[:notice] += " #{org_show_pending_billing_manager_invitation_url(current_organization_for_member_or_billing, invitation_token: invitation.token, via_email: "1")}"
          end
        end
      end

      redirect_to settings_org_billing_path(current_organization_for_member_or_billing)
    end
  end

  sig { void }
  def resend_invitation # rubocop:todo GitHub/UseRestfulActions
    if User.valid_email?(params[:id])
      email = params[:id]
    else
      user = User.find_by(login: params[:id])
    end

    invitation = this_organization.pending_invitation_for(user, email: email, role: :billing_manager)
    return render_404 unless invitation

    unless current_user.spammy? || invitation.opted_out?
      invitation.reset_token
      OrganizationMailer.invited_to_billing_manager_role(invitation, invitation.token).deliver_later
    end

    flash[:notice] = "Successfully sent #{invitation.email_or_invitee_name} another invite."
    redirect_to settings_org_billing_path(current_organization_for_member_or_billing)
  end

  private

  # Internal: Gets the organization we're operating inside based on an
  # `:organization_id`
  sig { returns(T.nilable(Organization)) }
  memoize def nilable_this_organization
    Organization.find_by(login: params[:organization_id])
  end

  sig { returns(Organization) }
  memoize def this_organization
    T.must(nilable_this_organization)
  end

  # Internal: Whether or not the provided user can be invited to the organization.
  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def invitable?(user)
    return false if user.nil?
    return true unless user.is_enterprise_managed?

    # EMU users can only be invited by other EMU users within the same enterprise
    user.enterprise_managed_business == current_user&.enterprise_managed_business
  end

  # Internal: This before_action renders a standard 404 page if
  # `this_organization` is nil.
  sig { void }
  def this_organization_required
    render_404 unless nilable_this_organization
  end

  sig { void }
  def check_ofac_flagged_user
    if current_user&.has_any_trade_restrictions?
      flash[:trade_controls_user_billing_error] = true
      redirect_to settings_user_billing_url
    end
  end

  sig { returns(T::Boolean) }
  def email_verification_required?
    authorization = ContentAuthorizer.authorize(
      current_user, :organization_invitation, :create
    )

    authorization.has_email_verification_error?
  end

  sig { void }
  def org_invite_rate_limited
    org_invite_rate_limit_policy.record_rate_limited(action_name, controller_name)

    view = create_view_model BillingManagers::NewView,
      organization: this_organization, rate_limited: true
    render "billing_managers/new", status: 429, locals: { view: view }
  end

  sig { returns(T.nilable(Organization)) }
  def invite_rate_limited_organization
    nilable_this_organization
  end

  sig { void }
  def ensure_two_factor_requirement_is_met
    unless this_organization.two_factor_requirement_met_by?(current_user)
      redirect_to org_show_pending_billing_manager_invitation_path(this_organization)
    end
  end
end
