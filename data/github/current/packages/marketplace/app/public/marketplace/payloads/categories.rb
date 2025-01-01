# typed: strict
# frozen_string_literal: true

module Marketplace
  module Payloads
    class Categories
      extend T::Helpers
      include GitHub::Memoizer
      include TextHelper

      sig do
        returns({
          apps: T::Array[Marketplace::Types::SerializedCategory],
          actions: T::Array[Marketplace::Types::SerializedCategory],
        })
      end
      def call
        {
          apps: categories_with_apps.map { |category| serialize_category(category) },
          actions: categories_with_actions.map { |category| serialize_category(category) },
        }
      end

      private

      sig { returns(T::Array[Marketplace::Category]) }
      def categories_with_apps
        Marketplace::Category
          .navigation_visible
          .joins(:listings)
          .merge(Marketplace::Listing.publicly_listed)
          .order(:name)
          .distinct
          .records
      end

      sig { returns(T::Array[Marketplace::Category]) }
      def categories_with_actions
        category_ids = cached_category_ids_with_listed_actions

        Marketplace::Category.navigation_visible.where(id: category_ids).order(:name).records
      end

      sig { params(category: Marketplace::Category).returns(Marketplace::Types::SerializedCategory) }
      def serialize_category(category)
        {
          name: category.name,
          slug: category.slug,
          description_html: github_simplified_markdown(category.description)
        }
      end

      sig { returns(String) }
      def action_categories_cache_key
        "marketplace_active_action_categories:#{Time.now.utc.end_of_hour.to_i}"
      end

      sig { returns(T::Array[Integer]) }
      def category_ids_with_listed_actions
        MarketplaceCategoriesRepositoryAction
          .joins(:repository_action)
          .merge(RepositoryAction.in_marketplace)
          .distinct
          .pluck(:marketplace_category_id)
      end

      sig { returns(T::Array[Integer]) }
      def cached_category_ids_with_listed_actions
        GitHub.cache.fetch(action_categories_cache_key) do
          category_ids_with_listed_actions
        end
      end
    end
  end
end
