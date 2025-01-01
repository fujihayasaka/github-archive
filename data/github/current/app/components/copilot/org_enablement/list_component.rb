# typed: strict
# frozen_string_literal: true

module Copilot
  module OrgEnablement
    class ListComponent < ApplicationComponent
      extend T::Sig

      delegate :linked_avatar_for, to: :helpers

      sig { params(business: ::Business, organizations: T::Array[::Organization], feature_requests: T::Hash[T.untyped, T.untyped]).void }
      def initialize(business:, organizations:, feature_requests: {})
        @business = business
        @organizations = organizations
        @feature_requests = T.let(feature_requests, T::Hash[T.untyped, T.untyped])
      end

      sig { returns(String) }
      memoize def organization_payload
        {
          organizations: @organizations.inject({}) do |acc, org|
            copilot_org = Copilot::Organization.new(org)
            acc[org.id] = {
              id: org.id,
              copilot_plan: copilot_org.copilot_enabled? ? copilot_org.copilot_plan : "disabled",
            }
            acc
          end,
          businessName: @business.slug
        }.to_json
      end
    end
  end
end
