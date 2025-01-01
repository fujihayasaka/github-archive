# typed: strict
# frozen_string_literal: true

class Sponsors::SettingsController < ApplicationController
  include Sponsors::AdminableControllerValidations

  before_action :non_waitlisted_sponsors_listing_required
  before_action :require_acceptance_into_sponsors_program
  before_action :add_csp_exceptions

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  CSP_EXCEPTIONS = T.let({
    form_action: [
      Billing::StripeConnect::Account::STRIPE_CONNECT_URL,
    ],
  }.freeze, T::Hash[Symbol, T::Array[String]])

  layout "layouts/sponsors"

  stylesheet_bundle :sponsors

  sig { void }
  def show
    sponsors_listing = T.must_because(sponsorable_sponsors_listing) do
      "required by `non_waitlisted_sponsors_listing_required` filter"
    end
    stripe_connect_accounts = sponsors_listing.stripe_connect_accounts
    GitHub::PrefillAssociations.prefill_batch_method(stripe_connect_accounts, :has_balance_in_stripe?)

    render "sponsors/settings/show", locals: {
      sponsorable: sponsorable,
      sponsors_listing: sponsors_listing,
      stripe_connect_accounts: stripe_connect_accounts,
      disable_stripe_links: disable_stripe_links?
    }
  end

  private

  sig { returns(T::Boolean) }
  def disable_stripe_links?
    sponsors_listing = T.must_because(sponsorable_sponsors_listing) do
      "required by `non_waitlisted_sponsors_listing_required` filter"
    end
    return false if sponsors_listing.adminable_by?(current_user)
    current_user.can_admin_sponsors_listings?
  end

  sig { returns(T.any(Symbol, GitHubSponsors::Types::Sponsorable)) }
  def target_for_conditional_access
    target_sponsorable = sponsorable
    return :no_target_for_conditional_access unless target_sponsorable # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    target_sponsorable
  end
end
