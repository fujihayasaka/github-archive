# typed: strict
# frozen_string_literal: true

class Orgs::Sponsorings::InvoicedBilling::BaseController < Orgs::Controller
  extend T::Sig

  before_action :sponsors_required
  before_action :ensure_actor_authorized

  layout "layouts/orgs/sponsorings/invoiced_billing"

  private

  sig { void }
  def ensure_actor_authorized
    render_404 unless this_organization.billing_manageable_by?(current_user)
  end
end
