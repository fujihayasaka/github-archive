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
        businessId: T.nilable(String),
        categories: T::Array[{
          name: String,
          slug: String
        }],
        copilotApp: T::Boolean,
        documentationUrl: T.nilable(String),
        euTrader: T.nilable(String),
        extendedDescription: T.nilable(String),
        fullDescription: T.nilable(String),
        id: Integer,
        installationCount: Integer,
        isAiHighRisk: T.nilable(String),
        isVerifiedOwner: T::Boolean,
        listableType: String,
        listingLogoUrl: T.nilable(String),
        llmsInUse: T.nilable(String),
        name: String,
        ownerImage: T.nilable(String),
        ownerLogin: T.nilable(String),
        ownerSafeProfileName: T.nilable(String),
        ownerType: T.nilable(String),
        pricingUrl: T.nilable(String),
        privacyPolicyUrl: T.nilable(String),
        publisher2faRequired: T.nilable(String),
        repositoryVisibility: T.nilable(String),
        repositoryUrl: T.nilable(String),
        shortDescription: T.nilable(String),
        slug: String,
        statusUrl: T.nilable(String),
        supportEmail: T.nilable(String),
        supportUrl: T.nilable(String),
        thirdPartyServices: T.nilable(String),
        tosUrl: T.nilable(String),
        traderAddress: T.nilable(String),
        transparencyDisclosure: T.nilable(String),
        type: String,
        verifiedProfileDomains: T::Array[String]
      }
    end

    SerializedAppPreview = T.type_alias do
      {
        bgColor: String,
        copilotApp: T::Boolean,
        id: Integer,
        isVerifiedOwner: T::Boolean,
        listingLogoUrl: T.nilable(String),
        name: String,
        shortDescription: T.nilable(String),
        slug: String,
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
        externalUsesPathPrefix: String,
        globalRelayId: String
      }
    end

    SerializedActionPreview = T.type_alias do
      {
        color: String,
        description: T.nilable(String),
        iconSvg: T.nilable(String),
        id: Integer,
        isVerifiedOwner: T::Boolean,
        name: String,
        slug: T.nilable(String),
        type: String,
      }
    end

    SerializedRepository = T.type_alias do
      {
        id: Integer,
        name: T.nilable(String),
        owner: T.nilable(String),
        isDiscussionsActive: T::Boolean,
        hasIssues: T::Boolean,
        hasSecurityPolicy: T::Boolean,
        isThirdParty: T::Boolean,
        isOrganization: T::Boolean,
        contributorsCount: Integer,
        topContributorsData: T::Array[T::Hash[Symbol, String]],
        openIssuesCount: Integer,
        openPullRequestsCount: Integer
      }
    end

    SerializedReleaseData = T.type_alias do
      {
        selectedRelease: T.nilable(SerializedRelease),
        latestRelease: SerializedRelease,
        releases: T::Array[SerializedRelease]
      }
    end

    SerializedRelease = T.type_alias do
      {
        tagName: String,
        name: T.nilable(String),
        isPrerelease: T::Boolean
      }
    end

    SerializedStarData = T.type_alias do
      {
        starredByCurrentUser: T::Boolean,
        currentUserAbleToStar: T::Boolean,
        currentUserEnterpriseName: T.nilable(String)
      }
    end

    SerializedPermissionsData = T.type_alias do
      {
        scope: String,
        permissionLevel: String,
        values: T::Array[String]
      }
    end

    ListingPreview = T.type_alias do
      T.any(SerializedAppPreview, SerializedActionPreview, T.nilable(GitHubModels::Types::ModelListing))
    end

    # Keep in sync with SearchResults in ui/packages/marketplace-common/types.ts
    Search = T.type_alias do
      {
        results: T::Array[Marketplace::Types::ListingPreview],
        total: Integer,
        totalPages: Integer,
        parsedQuery: T::Array[T.untyped],
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
        altText: T.nilable(String)
      }
    end

    PlanInfo = T.type_alias do
      {
        anyAccountEligibleForFreeTrial: T::Boolean,
        canSignEndUserAgreement: T::Boolean,
        emuOwnerButNotAdmin: T::Boolean,
        endUserAgreement: T.nilable({
          html: String,
          id: Integer,
          name: T.nilable(String),
          userSignedAt: T.nilable(ActiveSupport::TimeWithZone),
          version: String,
        }),
        freeTrialLength: String,
        freeTrialsUsed: T::Boolean,
        installationUrlRequirementMet: T::Boolean,
        isBuyable: T::Boolean,
        isLoggedIn: T::Boolean,
        isRegularEmuUser: T::Boolean,
        isUserBilledMonthly: T::Boolean,
        listingByGithub: T::Boolean,
        orderPreview: { quantity: T.nilable(Integer) },
        organizations: T::Array[
          {
            displayLogin: String,
            hasExtensibilityAccess: T::Boolean,
            image: T.nilable(String),
            isEnterpriseOwned: T::Boolean,
            installedForOrg: T::Boolean
          }
        ],
        plans: T::Array[Plan],
        selectedAccount: T.nilable(String),
        selectedPlanId: T.nilable(String),
        subscriptionItem: { onFreeTrial: T.nilable(T::Boolean) },
        userCanEditListing: T::Boolean,
        viewerFreeTrialDaysLeft: T.nilable(Integer),
        viewerHasPurchased: T::Boolean,
        anyOrgsPurchased: T::Boolean,
        viewerBilledOrganizations: T::Array[String],
        viewerHasPurchasedForAllOrganizations: T::Boolean,
        installedForViewer: T::Boolean,
        planIdByLogin: T::Hash[String, String],
        currentUser: T.nilable({ displayLogin: String, hasExtensibilityAccess: T::Boolean, image: T.nilable(String) })
      }
    end

    Plan = T.type_alias do
      {
        id: String,
        name: String,
        description: String,
        yearlyPriceInCents: Integer,
        monthlyPriceInCents: Integer,
        perUnit: T::Boolean,
        unitName: T.nilable(String),
        isPaid: T::Boolean,
        hasFreeTrial: T::Boolean,
        price: String,
        directBilling: T::Boolean,
        forOrganizationsOnly: T::Boolean,
        forUsersOnly: T::Boolean,
        bullets: T::Array[String]
      }
    end
  end
end
