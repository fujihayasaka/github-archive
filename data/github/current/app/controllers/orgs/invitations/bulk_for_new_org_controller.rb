# typed: true
# frozen_string_literal: true

class Orgs::Invitations::BulkForNewOrgController < Orgs::Controller
  include Orgs::InvitationsControllerMethods
  limit_invitation_roles :admin, :direct_member, :reinstate

  before_action :login_required
  before_action :organization_admin_required
  before_action :sudo_filter

  include Site::MicrosoftAnalyticsDependency
  before_action :allow_initial_cookie_consent
  before_action :enable_microsoft_analytics
  before_action :add_microsoft_analytics_csp_exceptions
  layout "enterprise_funnel"

  include Orgs::Invitations::RateLimiting
  setup_org_invite_rate_limiting only: [:create], filter: :rate_limiting_enabled?

  def create
    if params[:members]&.filter_map(&:presence).present?

      adjust_volume_plan_seats = GitHub.billing_enabled? && !this_organization.plan.legacy? && params[:members].length > this_organization.available_invitable_seats

      if adjust_volume_plan_seats && (!this_organization.billing_customer&.metered_plan? || current_user.feature_flag_enabled?(:enable_metered_adjust_plan_seat_via_org_invite, default: false))
        old_seat_count = this_organization.seats
        seat_delta = params[:members].length - this_organization.available_invitable_seats
        seat_change = Billing::PlanChange::SeatChange.new(this_organization, seats: old_seat_count + seat_delta)
        result = GitHub::Billing.change_seats(this_organization, seats: seat_change.seats, seat_delta: seat_delta, actor: current_user)

        if result.success?
          if this_organization.save
            seat_change_ga_label = [
              helpers.seats_volume_bucket(seat_change.old_seats),
              helpers.seats_volume_bucket(seat_change.seats)
            ].uniq.join(" -> ")

            helpers.publish_billing_seat_count_change_for(
              actor: current_user,
              user: this_organization,
              old_seat_count: old_seat_count,
              new_seat_count: seat_change.seats,
            )

            analytics_event(
              category: "Orgs",
              action: "upgrade seats",
              label: seat_change_ga_label,
            )
          end
        end
      end

      OrganizationBulkInviteJob.perform_later(current_user, this_organization, params[:members])

      n = params[:members].length
      if session[:copilot_flash_pay_info_message].blank?
        flash[:notice] = "You've invited #{n} #{"member".pluralize(n)}. They'll receive their invitation #{"email".pluralize(n)} shortly."
      end
    end

    if session[:return_to] == "copilot_business_signup"
      redirect_to copilot_business_signup_organization_payment_path(org: current_organization, **(session[:utm_memo] || {}))
    else
      redirect_to org_root_path(this_organization)
    end
  end

  private

  def rate_limiting_enabled?
    !GitHub.bypass_org_invites_enabled?
  end

  def org_invite_rate_limited
    org_invite_rate_limit_policy.record_rate_limited(action_name, controller_name)

    case action_name
    when "create"
      render "orgs/invitations/rate_limited", status: 429, locals: {
        organization: this_organization,
      }
    end
  end
end
