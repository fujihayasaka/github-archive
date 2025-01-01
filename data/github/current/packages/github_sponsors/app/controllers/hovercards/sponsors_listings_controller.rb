# typed: true
# frozen_string_literal: true

class Hovercards::SponsorsListingsController < ApplicationController
  include Hovercards::ConditionalAccessMethods
  include Sponsors::SharedControllerMethods

  before_action :sponsorable_required
  before_action :require_xhr
  before_action :approved_sponsors_listing_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:show]

  def show
    render "hovercards/sponsors_listings/show", locals: {
      sponsorable: sponsorable,
      sponsors_listing: sponsorable_sponsors_listing,
      goal: sponsorable_sponsors_listing&.active_goal,
    }, layout: false
  end

  private

  def target_for_conditional_access
    sponsorable
  end

  def require_active_external_identity_session?
    true
  end
end
