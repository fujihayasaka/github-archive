# typed: strict
# frozen_string_literal: true

require File.expand_path("query_binder.rb", __dir__)
Dir[File.expand_path("subscriptions/*.rb", __dir__)].each { |f| require f }

module ServiceCatalog
  class Client
    # SubscriptionQueryBinder contains methods for accessing subscriptions.
    class SubscriptionsQueryBinder < QueryBinder
      # A default subscription detail fragment.
      SUBSCRIPTION_DETAIL_FRAGMENT = <<~GRAPHQL
        fragment SubscriptionDetail on Subscription {
          id
          destination
          destinationKind
          frequency
          kind
          lastProcessed
          serviceQuery
          scorecardFilter
        }
      GRAPHQL
    end
  end
end
