# typed: strict
# frozen_string_literal: true

module Marketplace
  class Types
    extend T::Helpers

    class ListingTypes < T::Enum
      enums do
        MarketplaceListing = new("marketplace_listing")
        RepositoryAction = new("repository_action")
      end
    end

    SerializedAppListing = T.type_alias do
      {
        bgColor: String,
        copilotApp: T::Boolean,
        documentationUrl: T.nilable(String),
        extendedDescription: T.nilable(String),
        fullDescription: T.nilable(String),
        id: Integer,
        installationCount: Integer,
        isVerifiedOwner: T::Boolean,
        listingLogoUrl: T.nilable(String),
        name: String,
        ownerLogin: T.nilable(String),
        pricingUrl: T.nilable(String),
        primaryCategory: T.nilable(String),
        privacyPolicyUrl: T.nilable(String),
        secondaryCategory: T.nilable(String),
        shortDescription: T.nilable(String),
        slug: String,
        statusUrl: T.nilable(String),
        supportUrl: T.nilable(String),
        tosUrl: T.nilable(String),
        type: String
      }
    end

    SerializedActionListing = T.type_alias do
      {
        categories: T::Array[T::Hash[Symbol, String]],
        color: String,
        description: T.nilable(String),
        iconSvg: T.nilable(String),
        id: Integer,
        isVerifiedOwner: T::Boolean,
        name: String,
        ownerLogin: T.nilable(String),
        slug: T.nilable(String),
        stars: Integer,
        type: String,
      }
    end

    SerializedRepository = T.type_alias do
      {
        name: T.nilable(String),
        owner: T.nilable(String),
        isDiscussionsActive: T::Boolean,
        hasIssues: T::Boolean,
        hasSecurityPolicy: T::Boolean,
        mitLicensePath: T.nilable(String),
        isThirdParty: T::Boolean,
        isOrganization: T::Boolean,
        contributorsCount: Integer,
        topContributorsData: T::Array[T::Hash[Symbol, String]],
      }
    end

    SerializedDelistActionData = T.type_alias do
      {
        hydroAttrs: T::Hash[String, String],
        repoAdminableByViewer: T::Boolean
      }
    end

    Listing = T.type_alias do
      T.any(SerializedAppListing, SerializedActionListing, T.nilable(GitHubModels::Types::SerializedListing))
    end

    Search = T.type_alias do
      {
        results: T::Array[Marketplace::Types::Listing],
        total: Integer,
        totalPages: Integer
      }
    end

    SerializedCategory = T.type_alias do
      {
        name: String,
        slug: String,
        description_html: String
      }
    end

    SerializedScreenshot = T.type_alias do
      {
        id: Integer,
        src: String,
        caption: T.nilable(String),
        alt_text: T.nilable(String)
      }
    end

    PlanInfo = T.type_alias do
      {
        any_account_eligible_for_free_trial: T::Boolean,
        can_sign_end_user_agreement: T::Boolean,
        emu_owner_but_not_admin: T::Boolean,
        end_user_agreement: T.nilable({
          html: String,
          id: Integer,
          name: T.nilable(String),
          user_signed_at: T.nilable(ActiveSupport::TimeWithZone),
          version: String,
        }),
        free_trial_length: String,
        free_trials_used: T::Boolean,
        installation_url_requirement_met: T::Boolean,
        is_buyable: T::Boolean,
        is_logged_in: T::Boolean,
        is_regular_emu_user: T::Boolean,
        is_user_billed_monthly: T::Boolean,
        listing_by_github: T::Boolean,
        order_preview: { quantity: T.nilable(Integer) },
        organizations: T::Array[{ display_login: String, has_extensibility_access: T::Boolean, image: T.nilable(String) }],
        plans: T::Array[Plan],
        selected_account: T.nilable(String),
        selected_plan_id: T.nilable(String),
        subscription_item: { on_free_trial: T.nilable(T::Boolean) },
        support_email: T.nilable(String),
        user_can_edit_listing: T::Boolean,
        viewer_free_trial_days_left: T.nilable(Integer),
        viewer_has_purchased: T::Boolean,
        any_orgs_purchased: T::Boolean,
        viewer_billed_organizations: T::Array[String],
        viewer_has_purchased_for_all_organizations: T::Boolean,
        installed_for_viewer: T::Boolean,
        plan_id_by_login: T::Hash[String, String],
        current_user: T.nilable({ display_login: String, has_extensibility_access: T::Boolean, image: T.nilable(String) })
      }
    end

    Plan = T.type_alias do
      {
        id: String,
        name: String,
        description: String,
        yearly_price_in_cents: Integer,
        monthly_price_in_cents: Integer,
        per_unit: T::Boolean,
        unit_name: T.nilable(String),
        is_paid: T::Boolean,
        has_free_trial: T::Boolean,
        price: String,
        direct_billing: T::Boolean,
        for_organizations_only: T::Boolean,
        for_users_only: T::Boolean,
        bullets: T::Array[String]
      }
    end
  end
end
