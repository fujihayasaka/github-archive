# frozen_string_literal: true
require "graphql/enterprise"

module App
  # Type system:
  Definition = <<-GRAPHQL
    type Subscription {
      counterIncremented(id: ID!): Counter
    }
    type Counter {
      id: ID!
      value: Int!
    }
    type Query {
      counter(id: ID!): Counter
    }
    type Mutation {
      incrementCounter(id: ID!): Counter
    }
  GRAPHQL

  # Resolve functions:
  Resolvers = {
    "Subscription" => {
      "counterIncremented" => ->(o, a, c) {
        if c.query.subscription_update?
          o
        else
          c.skip
        end
      }
    },
    "Mutation" => {
      "incrementCounter" => ->(o, a, c) {
        counter = App::Counter.find(a[:id])
        counter.increment
        counter
      }
    },
    "Query" => {
      "counter" => ->(o, a, c) { App::Counter.find(a[:id]) }
    },
    "Counter" => {
      "value" => ->(o, a, c) { o.value },
      "id" => ->(o, a, c) { o.id },
    }
  }

  # Schema, defined from the definition then updated with subscription info
  Schema = GraphQL::Schema.from_definition(Definition, default_resolve: Resolvers)
  Schema.class_eval do
    # use GraphQL::Enterprise::MutationLimiter, redis: Redis.new
    if ENV["TESTING_ABLY"]
      use GraphQL::Pro::AblySubscriptions, redis: Redis.new, broadcast: true, default_broadcastable: true, ably: Ably::Rest.new(key: 'u0LX_A.Cdshgw:DHQ5clPJTuPFB0A8')
    else
      use GraphQL::Pro::PusherSubscriptions, redis: Redis.new, broadcast: true, default_broadcastable: true, show_broadcast_subscribers_count: true # , pusher: ...
    end
  end
end
