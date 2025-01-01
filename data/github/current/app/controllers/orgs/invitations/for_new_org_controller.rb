# typed: true
# frozen_string_literal: true

class Orgs::Invitations::ForNewOrgController < Orgs::Controller
  include Orgs::InvitationsControllerMethods
  limit_invitation_roles :admin, :direct_member, :reinstate

  before_action :login_required
  before_action :organization_admin_required

  include Orgs::Invitations::RateLimiting
  setup_org_invite_rate_limiting \
    only: [:create],
    filter: :rate_limiting_enabled?

  def create
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

  private

  # Filter used with `setup_org_invite_rate_limiting`
  def rate_limiting_enabled?
    !GitHub.bypass_org_invites_enabled?
  end

  def email_verification_required?
    current_user.requires_verification_to_invite_by_email?
  end

  def org_invite_rate_limited
    org_invite_rate_limit_policy.record_rate_limited(action_name, controller_name)

    case action_name
    when "create"
      render status: 429, json: {
        message_html: render_to_string(
          partial: "orgs/invitations/rate_limited_message",
          formats: [:html],
        ),
      }
    end
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
end
