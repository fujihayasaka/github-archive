# typed: strict
# frozen_string_literal: true

class Orgs::Sponsorings::BaseController < Orgs::Controller
  layout "layouts/orgs/sponsorings/dashboard"

  private

  # Private: Can the current user manage sponsoring for this organization?
  sig { returns(T::Boolean) }
  def viewer_can_manage_org_sponsoring?
    return false unless logged_in?
    this_organization.billing_manageable_by?(current_user) ||
      current_user.potential_sponsor_ids.include?(this_organization.id)
  end

  sig { returns(T::Boolean) }
  def staff_view?
    return false if this_organization.billing_manageable_by?(current_user)
    current_user.can_admin_sponsors_listings?
  end
  helper_method :staff_view?

  sig { returns(T::Boolean) }
  memoize def active_invoiced_sponsors_agreement?
    this_organization.active_invoiced_sponsors_agreement?
  end
  helper_method :active_invoiced_sponsors_agreement?
end
