# typed: strict
# frozen_string_literal: true

class Sponsors::Accounts::SignupComponent < ApplicationComponent
  include DocsUrlHelper

  sig { returns GitHubSponsors::Types::Sponsorable }
  attr_reader :sponsorable

  sig { returns T.nilable(SponsorsListing) }
  attr_reader :listing

  sig do
    params(
      sponsorable: GitHubSponsors::Types::Sponsorable,
      listing: T.nilable(SponsorsListing),
    ).void
  end
  def initialize(sponsorable:, listing: nil)
    @sponsorable = sponsorable
    @listing = listing
  end

  sig { returns String }
  def call
    content_tag(:div, **test_selector_data_hash("sponsors-signup")) do
      render_react_partial(
        name: "sponsors-signup",
        props: react_partial_props,
        disable_ssr: true,
      )
    end
  end

  sig { returns T::Hash[Symbol, T.untyped] }
  def react_partial_props
    props = {
      formData: {
        formAction: form_action,
        countries: countries,
        fiscalHosts: fiscal_hosts,
      },
      sponsorableData: {
        isUser: sponsorable.user?,
        possibleContactEmails: possible_contact_emails,
        contactEmailUpdatePath: contact_email_update_path,
      },
      docsLinks: {
        about: docs_url("sponsors/about-for-oss-contributors"),
        fiscalHosts: docs_url("sponsors/fiscal-hosts")
      },
    }

    if sponsors_listing_data.present?
      props.merge!(sponsorsListingData: sponsors_listing_data)
    end

    props
  end

  private

  sig { returns T::Hash[String, { id: T.nilable(Integer) }] }
  def possible_contact_emails
    if sponsorable.user?
      sponsorable.possible_sponsors_emails.each_with_object({}) do |user_email, hash|
        hash[user_email.email] = { email: user_email.email, type: "user", id: user_email.id }
      end
    else
      billing_email = sponsorable.billing_email
      if billing_email
        { billing_email => { email: billing_email, type: "billing" } }
      else
        {}
      end
    end
  end

  sig { returns T::Hash[String, { name: String, stripe_supported: T::Boolean }] }
  def countries
    unsanctioned = TradeControls::Countries.currently_unsanctioned
    countries = unsanctioned.each_with_object({}) do |(country_name, alpha2, _, _), hash|
      hash[alpha2] = { countryCode: alpha2, name: country_name, stripeSupported: false }
    end
    Billing::StripeConnect::Account.supported_countries.each do |alpha2|
      countries[alpha2][:stripeSupported] = true
    end
    countries
  end

  sig { returns T::Hash[Integer, { name: String }] }
  def fiscal_hosts
    listings = SponsorsListing.fiscal_hosts_visible_for_signup
      .ordered_by_sponsorable_login
      .includes(sponsorable: :profile)
    listings.each_with_object({}) do |listing, hash|
      hash[listing.sponsorable_login] = { name: listing.sponsorable_name, sponsorsListingId: listing.id }
    end
  end

  sig { returns String }
  def contact_email_update_path
    if sponsorable.user?
      Rails.application.routes.url_helpers.settings_email_preferences_path
    else
      Rails.application.routes.url_helpers.settings_org_profile_path(sponsorable.display_login)
    end
  end

  sig { returns T.nilable(T::Hash[Symbol, T::untyped]) }
  def sponsors_listing_data
    sponsors_listing = listing
    return nil unless sponsors_listing&.persisted?
    sponsors_listing.serialize_for_signup
  end

  sig { returns String }
  memoize def form_action
    Rails.application.routes.url_helpers.sponsorable_signup_path(sponsorable)
  end
end
