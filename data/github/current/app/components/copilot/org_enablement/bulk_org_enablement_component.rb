# typed: strict
# frozen_string_literal: true

module Copilot
  module OrgEnablement
    class BulkOrgEnablementComponent < ApplicationComponent

      delegate :linked_avatar_for, to: :helpers

      sig { params(business: ::Business, organizations: T::Array[::Organization], feature_requests: T::Hash[T.untyped, T.untyped]).void }
      def initialize(business:, organizations:, feature_requests: {})
        @organizations = organizations
        @business = business
        @copilot_business = T.let(Copilot::Business.new(@business), Copilot::Business)
        @feature_requests = T.let(feature_requests, T::Hash[T.untyped, T.untyped])
      end

      sig { params(action: String).returns(T::Hash[Symbol, String]) }
      def bulk_actions_data(action:)
        {
          **analytics_click_attributes(
            category: "#{action}_copilot_orgs",
            action: "click_to_#{action}_copilot_orgs",
            label: "ref_page:#{request&.fullpath};ref_cta:#{action}_copilot_orgs;ref_loc:copilot_for_business"
          )
        }
      end
    end
  end
end
