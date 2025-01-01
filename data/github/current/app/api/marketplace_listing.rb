# typed: true
# frozen_string_literal: true

class Api::MarketplaceListing < Api::App
  include ::Api::App::MarketplaceListingHelpers

  PlansQuery = PlatformClient.parse <<-'GRAPHQL'
    query($listingSlug: String!, $plansLimit: Int!, $planBulletsLimit: Int!, $numericPage: Int) {
      marketplaceListing(slug: $listingSlug) {
        ...Api::Serializer::MarketplaceListingDependency::MarketplaceListingFragment
        plans(first: $plansLimit, numericPage: $numericPage) {
          totalCount
          edges {
            node {
              ...Api::Serializer::MarketplaceListingDependency::MarketplaceListingPlanFragment
            }
          }
        }
      }
    }
  GRAPHQL

  get "/marketplace_listing/plans", operation_id: "apps/list-plans" do
    require_marketplace_listing!
    control_access :apps_audited, resource: current_marketplace_listing, allow_integrations: false, allow_user_via_granular_actor: false
    variables = {
      "listingSlug" => current_marketplace_listing.slug,
      "plansLimit" => pagination[:per_page] || Marketplace::ListingPlan::PLAN_LIMIT_PER_LISTING,
      "planBulletsLimit" => Marketplace::ListingPlanBullet::BULLET_LIMIT_PER_LISTING_PLAN,
      "numericPage" => pagination[:page],
    }

    results = platform_execute(PlansQuery, variables: variables)

    if results.errors.all.any?
      deliver_error! 422, errors: results.errors.all.values.flatten
    end

    listing = results.data.marketplace_listing
    plans = nil

    if listing
      paginator.collection_size = listing.plans.total_count
      plans = listing.plans.edges.map(&:node)
    end

    deliver :graphql_marketplace_listing_plan_hash, plans
  end

  PlanSubscriptionItemsForAccountQuery = PlatformClient.parse <<-'GRAPHQL'
    query($accountId: Int!, $listingId: Int!, $planBulletsLimit: Int!) {
      marketplacePurchase(accountId: $accountId, marketplaceListingId: $listingId) {
        ... on SubscriptionItem {
          ...Api::Serializer::MarketplaceListingDependency::SubscriptionItemFragment
        }
      }
    }
  GRAPHQL

  get "/marketplace_listing/accounts/:account_id", operation_id: "apps/get-subscription-plan-for-account" do
    account = find_account!(param_name: :account_id)
    control_access :apps_audited, resource: account, allow_integrations: false, allow_user_via_granular_actor: false
    require_marketplace_listing!

    variables = {
      "accountId" => account.id,
      "listingId" => current_marketplace_listing.id,
      "planBulletsLimit" => Marketplace::ListingPlanBullet::BULLET_LIMIT_PER_LISTING_PLAN,
    }

    results = platform_execute(PlanSubscriptionItemsForAccountQuery, variables: variables)

    if results.errors.all.any?
      deliver_error! 422, errors: results.errors.all.values.flatten
    end

    item = results.data.marketplace_purchase

    deliver :graphql_subscription_item_hash, item
  end

  PlanSubscriptionItemsQuery = PlatformClient.parse <<-'GRAPHQL'
    query($planId: ID!, $subscriptionItemsCount: Int!, $planBulletsLimit: Int!, $numericPage: Int, $orderBy: SubscriptionItemOrder) {
      plan: node(id: $planId) {
        ... on MarketplaceListingPlan {
          ...Api::Serializer::MarketplaceListingDependency::MarketplaceListingPlanFragment
          subscriptionItems(first: $subscriptionItemsCount, numericPage: $numericPage, orderBy: $orderBy) {
            totalCount
            edges {
              node {
                ...Api::Serializer::MarketplaceListingDependency::SubscriptionItemFragment
              }
            }
          }
        }
      }
    }
  GRAPHQL

  get "/marketplace_listing/plans/:plan_id/accounts", operation_id: "apps/list-accounts-for-plan" do
    require_marketplace_listing!
    control_access :apps_audited, resource: current_marketplace_listing, allow_integrations: false, allow_user_via_granular_actor: false

    plan = find_plan!(param_name: :plan_id)

    variables = {
      "planId" => plan.global_relay_id,
      "subscriptionItemsCount" => pagination[:per_page] || MAX_PER_PAGE,
      "planBulletsLimit" => Marketplace::ListingPlanBullet::BULLET_LIMIT_PER_LISTING_PLAN,
      "numericPage" => pagination[:page],
      "orderBy" => T.let(nil, T.untyped)
    }

    if params[:sort].present?
      if %w[asc desc].include?(params[:direction])
        direction = params[:direction].upcase
      end

      unless %w[created updated].include?(params[:sort])
        deliver_error! 422, message: "Invalid sort: #{params[:sort].inspect}.", documentation_url: @documentation_url
      end

      rest_to_graphql_mapping = { "created" => "CREATED_AT", "updated" => "UPDATED_AT" }
      variables["orderBy"] = { field: rest_to_graphql_mapping[params[:sort]], direction: (direction || "ASC") }
    end

    results = platform_execute(PlanSubscriptionItemsQuery, variables: variables)

    if results.errors.all.any?
      deliver_error! 422, errors: results.errors.all.values.flatten
    end

    plan = results.data.plan

    items = if plan
      paginator.collection_size = plan.subscription_items.total_count
      plan.subscription_items.edges.map(&:node)
    end

    deliver :graphql_subscription_item_hash, items, { plan: plan }
  end
end
