# typed: true
# frozen_string_literal: true

class Sponsors::DashboardsController < ApplicationController
  include Sponsors::AdminableControllerValidations
  include TradeControlsControllerMethods

  prepend_before_action :login_required
  before_action :non_banned_sponsors_listing_required
  before_action :non_waitlisted_sponsors_listing_required
  before_action :require_acceptance_into_sponsors_program
  before_action :add_csp_exceptions
  skip_before_action :enabled_sponsors_listing_required, only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  CSP_EXCEPTIONS = {
    form_action: [
      Billing::StripeConnect::Account::STRIPE_CONNECT_URL,
    ] + Sponsors::ShareButtonComponent::SHARE_URL_BY_SOCIAL.values,
    frame_src: [
      "#{GitHub.scheme}://#{GitHub.host_name}",
    ]
  }.freeze

  layout "layouts/sponsors"

  stylesheet_bundle :sponsors

  def show
    instrument_billing_form_loaded(flow: "SPONSORABLE")

    render "sponsors/dashboards/show", locals: {
      sponsorable: sponsorable,
      sponsors_listing: sponsorable_sponsors_listing,
    }
  end

  private

  sig { returns T.any(Symbol, GitHubSponsors::Types::Sponsorable) }
  def target_for_conditional_access
    sponsorable || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  sig { override.returns(GitHubSponsors::Types::Sponsorable) }
  def target
    T.must_because(self.sponsorable) { "#require_acceptance_into_sponsors_program ensures non-nil" }
  end
end
