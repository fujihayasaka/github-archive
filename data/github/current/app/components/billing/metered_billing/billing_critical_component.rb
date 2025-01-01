# typed: true
# frozen_string_literal: true

module Billing
  module MeteredBilling
    class BillingCriticalComponent < ApplicationComponent
      include Billing::TrustTierDependency

      sig { returns(T.nilable(User)) }
      attr_reader :current_user

      sig { returns(Repository) }
      attr_reader :current_repository


      def initialize(current_user:, current_repository:)
        @current_user = current_user
        @current_repository = current_repository
      end

      def render?
        show_trust_tier_banner?(@current_repository.owner.billable_owner)
      end

      def current_user_admin?
        @current_repository.owner.billable_owner.adminable_by?(@current_user)
      end
    end
  end
end
