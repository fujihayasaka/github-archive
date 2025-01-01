# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Conditions
    # Helper to create a targetable object for a Organization
    # Long-term, it may make sense to have Organization implement Targetable directly if we choose to use
    # Targetable as a universal interface for all targetable objects
    class Targets::Organization

      include Targetable

      sig { params(organization: Organization).void }
      def initialize(organization:)
        @organization = organization
      end

      sig { override.returns(T::Hash[RuleEngine::Conditions::Targetable::Attribute, T.untyped]) }
      def targetable_attributes
        {
          Attribute::Organization => @organization,
        }
      end

      sig { override.returns(Promise[T.nilable(RuleEngine::Conditions::Targetable)]) }
      def async_targetable_parent
        @organization.async_business.then do |business|
          next nil if business.nil?
          Targets::Enterprise.new(business: business)
        end
      end
    end
  end
end
