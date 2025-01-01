# typed: strict
# frozen_string_literal: true

module GitHubModels
  module Payloads
    class Index

      sig { returns(T.nilable(User)) }
      attr_reader :current_user

      sig { returns(T::Array[GitHubModels::Types::Model]) }
      attr_reader :models

      sig { params(current_user: T.nilable(User), models: T::Array[GitHubModels::Types::Model]).void }
      def initialize(current_user:, models:)
        @current_user = current_user
        @models = models
      end

      sig do
        returns({
          categories: {
            apps: T::Array[Marketplace::Types::SerializedCategory],
            actions: T::Array[Marketplace::Types::SerializedCategory],
          },
          models: T::Array[GitHubModels::Types::Model]
        })
      end
      def call
        {
          categories: Marketplace::Payloads::Categories.new.call,
          models: filtered_models
        }
      end

      private

      sig { returns(T::Array[GitHubModels::Types::Model]) }
      def filtered_models
        visibility_map = AzureModels::CatalogItem.visibility_map(current_user)

        models.select do |model|
          visibility_map["#{model[:registry]}/#{model[:name]}"]
        end
      end
    end
  end
end
