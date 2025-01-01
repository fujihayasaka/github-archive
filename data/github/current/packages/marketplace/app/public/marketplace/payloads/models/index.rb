# typed: strict
# frozen_string_literal: true

module Marketplace
  module Payloads
    class Models::Index
      extend T::Sig

      sig { returns(T.nilable(User)) }
      attr_reader :current_user

      sig { returns(T::Array[Marketplace::Types::AzureModels::Model]) }
      attr_reader :models

      sig { returns(T::Boolean) }
      attr_reader :on_waitlist

      sig { params(current_user: T.nilable(User), models: T::Array[Marketplace::Types::AzureModels::Model]).void }
      def initialize(current_user:, models:)
        @current_user = current_user
        @models = models
        @on_waitlist = T.let(current_user_on_waitlist?, T::Boolean)
      end

      sig do
        returns({
          categories: {
            apps: T::Array[Marketplace::Types::SerializedCategory],
            actions: T::Array[Marketplace::Types::SerializedCategory],
          },
          models: T.untyped,
          on_waitlist: T::Boolean,
        })
      end
      def call
        {
          categories: Marketplace::Payloads::Categories.new.call,
          models: models,
          on_waitlist: on_waitlist,
        }
      end

      private

      sig { returns(T::Boolean) }
      def current_user_on_waitlist?
        return false unless current_user.present?

        EarlyAccessMembership.on_waitlist?(::Marketplace::ModelsBeta.new.feature_slug, T.must(current_user))
      end
    end
  end
end
