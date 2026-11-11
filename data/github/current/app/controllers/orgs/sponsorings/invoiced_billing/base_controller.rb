# typed: strict
# frozen_string_literal: true

class Orgs::Sponsorings::InvoicedBilling::BaseController < Orgs::Controller
  before_action :sponsors_required
  before_action :ensure_actor_authorized

  layout "layouts/orgs/sponsorings/invoiced_billing"

  private

  sig { void }
  def ensure_actor_authorized
    return if this_organization.billing_manageable_by?(current_user)
    return if logged_in? && current_user.potential_sponsor_ids.include?(this_organization.id)
    render_404
  end
end
