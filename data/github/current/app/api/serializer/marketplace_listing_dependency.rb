# typed: true
# frozen_string_literal: true

module Api::Serializer::MarketplaceListingDependency
  extend T::Helpers
  requires_ancestor { Api::Serializer::RepositoriesDependency }

  MarketplaceListingFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on MarketplaceListing {
      databaseId
      name
      slug
    }
  GRAPHQL

  MarketplaceListingPlanFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on MarketplaceListingPlan {
      id
      databaseId
      number
      name
      description
      priceModel
      hasFreeTrial
      yearlyPriceInCents
      monthlyPriceInCents
      state
      unitName
      bullets(first: $planBulletsLimit) {
        edges {
          node {
            value
          }
        }
      }
    }
  GRAPHQL

  # Public: Build the hash of a Marketplace::ListingPlan
  #
  # input - a Marketplace::ListingPlan GraphQL object
  #
  # Contains the numeric ID, and the human-readable name
  #
  # Returns a hash

  def graphql_marketplace_listing_plan_hash(plan, options = {})
    plan = MarketplaceListingPlanFragment.new(plan)
    bullets = plan.bullets.edges.map(&:node)

    options = T.unsafe(Api::SerializerOptions).from(options)

    {
      url: url("/marketplace_listing/plans/#{plan.database_id}", options),
      accounts_url: url("/marketplace_listing/plans/#{plan.database_id}/accounts", options),
      id: plan.database_id,
      number: plan.number,
      name: plan.name,
      description: plan.description,
      monthly_price_in_cents: plan.monthly_price_in_cents,
      yearly_price_in_cents: plan.yearly_price_in_cents,
      price_model: plan.price_model,
      has_free_trial: plan.has_free_trial,
      unit_name: plan.unit_name,
      state: plan.state.downcase,
      bullets: bullets.map(&:value),
    }
  end

  SubscriptionItemFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on SubscriptionItem {
      isInstalled
      billingCycle
      nextBillingDate
      onFreeTrial
      freeTrialEndsOn
      quantity
      updatedAt
      marketplaceListingPlan: subscribable {
        ... on MarketplaceListingPlan {
          ...Api::Serializer::MarketplaceListingDependency::MarketplaceListingPlanFragment
        }
      }
      marketplacePendingChange {
        id
        quantity
        activeOn
        marketplaceListingPlan: subscribable {
          ... on MarketplaceListingPlan {
            ...Api::Serializer::MarketplaceListingDependency::MarketplaceListingPlanFragment
          }
        }
      }
      account {
        ... on User {
          id
          databaseId
          login
          email
        }
        ... on Organization {
          id
          databaseId
          login
          organizationBillingEmail
          admins(first: 5) {
            edges {
              node {
                ... on User {
                  databaseId
                  login
                  email
                }
              }
            }
          }
        }
      }
    }
  GRAPHQL

  # Public: Build the hash of a subscription item for a marketplace listing
  #
  # input - a subscription item graphql object
  #
  # Contains the numeric ID, and the human-readable name
  #
  # Returns a hash
  def graphql_subscription_item_hash(item, options = {})
    item    = SubscriptionItemFragment.new(item)
    options = T.unsafe(Api::SerializerOptions).from(options)
    account = item.account
    plan    = MarketplaceListingPlanFragment.new(options[:plan] || item.marketplace_listing_plan) # Saves looking up the bullets for each item

    {}.tap do |opts|
      opts[:url]   = url_for(account, options)
      opts[:type]  = account.class.type.graphql_name
      opts[:id]    = account.database_id
      # Hash is used specifically for GraphQL and login in GraphQL already return display login
      opts[:login] = account.login # rubocop:disable GitHub/DoNotAllowLogin

      if account.is_a?(Api::App::PlatformTypes::User)
        opts[:email] = email(account)
      end

      opts[:marketplace_pending_change] = graphql_marketplace_pending_change_hash(item.marketplace_pending_change)

      opts[:marketplace_purchase] = {}.tap do |purchase|
        purchase[:billing_cycle]      = billing_cycle(item)
        purchase[:unit_count]         = item.quantity
        purchase[:on_free_trial]      = item.on_free_trial
        purchase[:free_trial_ends_on] = item.free_trial_ends_on
        purchase[:is_installed]       = item.is_installed?
        purchase[:updated_at] = time(item.updated_at)

        if plan && plan.price_model == "FREE"
          purchase[:next_billing_date] = nil
        else
          purchase[:next_billing_date] = time(item.next_billing_date)
        end

        if plan
          purchase[:plan] = graphql_marketplace_listing_plan_hash(plan)
        end
      end

      if account.is_a?(Api::App::PlatformTypes::Organization)
        opts[:organization_billing_email] = account.organization_billing_email
      end
    end
  end

  def graphql_marketplace_pending_change_hash(pending_change)
    return nil unless pending_change.present?
    plan = MarketplaceListingPlanFragment.new(pending_change.marketplace_listing_plan)

    {}.tap do |opts|
      opts[:id] = pending_change.id
      opts[:unit_count] = pending_change.quantity
      opts[:plan] = graphql_marketplace_listing_plan_hash(plan)
      opts[:effective_date] = time(pending_change.active_on)
    end
  end

  # Public: Build the hash for a marketplace purchase
  #
  # input - a subscription item graphql object
  #
  # Contains the numeric ID, and the human-readable name
  #
  # Returns a hash
  def graphql_marketplace_purchase_hash(item, options = {})
    item    = SubscriptionItemFragment.new(item)
    options = T.unsafe(Api::SerializerOptions).from(options)
    plan    = item.marketplace_listing_plan
    account = item.account

    # Hash is used specifically for GraphQL and login in GraphQL already returns display login
    {}.tap do |opts|
      opts[:account] = {
        url:     url_for(account, options),
        type:    account.class.type.graphql_name,
        id:      account.database_id,
        node_id: account.id,
        login:   account.login, # rubocop:disable GitHub/DoNotAllowLogin
      }
      opts[:billing_cycle]      = billing_cycle(item)
      opts[:unit_count]         = item.quantity
      opts[:next_billing_date]  = time(item.next_billing_date)
      opts[:on_free_trial]      = item.on_free_trial
      opts[:free_trial_ends_on] = item.free_trial_ends_on
      opts[:updated_at] = time(item.updated_at)

      if account.is_a?(Api::App::PlatformTypes::Organization)
        opts[:account][:organization_billing_email] = account.organization_billing_email
      end

      opts[:plan] = graphql_marketplace_listing_plan_hash(plan)
    end
  end

  private

  def billing_cycle(item)
    case item.billing_cycle
    when User::BillingDependency::MONTHLY_PLAN
      "monthly"
    when User::BillingDependency::YEARLY_PLAN
      "yearly"
    end
  end

  def email(account)
    account.email if account.is_a?(Api::App::PlatformTypes::User) && account.email.present?
  end

  def url_for(obj, options)
    url_prefix = obj.is_a?(Api::App::PlatformTypes::Organization) ? "orgs" : "users"
    # Hash is used specifically for GraphQL and login in GraphQL already return display login
    url(Api::LegacyEncode.encode("/#{url_prefix}/#{obj.login}", /\[|\]/), options) # rubocop:disable GitHub/DoNotAllowLogin
  end
end
