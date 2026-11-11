# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class SecurityAdvisoryCredits < Resolvers::Base
      type Connections.define(Objects::AdvisoryCredit), null: false

      argument :order_by, Inputs::AdvisoryCreditOrder,
        "Ordering options for the returned credits.",
        required: false,
        default_value: { field: "id" }

      def resolve(order_by:)
        object.credits.accepted
      end

    end
  end
end
