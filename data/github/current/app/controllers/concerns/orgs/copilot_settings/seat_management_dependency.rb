# typed: strict
# frozen_string_literal: true

module Orgs::CopilotSettings::SeatManagementDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  include GitHub::Memoizer

  requires_ancestor { Orgs::Controller }

  private

  sig { returns(Copilot::Organization) }
  memoize def copilot_organization
    T.must_because(current_copilot_organization) { "#org_admins_only ensures non-nil" }
  end

  sig { params(status: Integer).void }
  def render_index_json(status: 200)
    payload = Copilot::Organizations::SeatManagement::Payload.new(organization: this_organization, params: params,
      current_user: current_user).call
    render json: payload, status: status
  end

  sig { void }
  def check_not_legacy_plan
    render_404 if current_organization.plan.legacy?
  end

  sig { void }
  def check_copilot_available
    render_404 unless copilot_available?
  end

  sig { returns(T::Boolean) }
  def copilot_available?
    return false unless user = current_user
    return true if copilot_organization.can_enable_org_to_assign_seats?(user)
    return true if copilot_organization.can_request_copilot_from_enterprise?(user)

    copilot_organization.has_copilot_for_business? || copilot_organization.has_trial?
  end

  sig { params(invitations: T::Array[::OrganizationInvitation]).void }
  def unassign_invitations(invitations)
    invitations.each do |invitation|
      copilot_organization.unassign([invitation], current_user)

      # let's make sure there aren't any failed invitations we also need to unassign
      this_organization.failed_invitations.where(email: invitation.email).map do |failed_invite|
        copilot_organization.unassign([failed_invite], current_user)
      end
    end
  end
end
