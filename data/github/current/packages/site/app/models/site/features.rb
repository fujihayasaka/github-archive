# typed: true
# frozen_string_literal: true

module Site
  class Features
    DATA_PATH = "config/site/features.yml"

    def self.data
      @@data ||= YAML::load_file(DATA_PATH)
    end

    def self.category_item_collections
      self.data.map do |category_item_collection|
        CategoryItemCollection.new(
          id: category_item_collection["id"],
          items: category_item_collection["items"].map { |item| Site::Features::CategoryItemCollection::Item.new(item.symbolize_keys) }
        )
      end
    end

    def self.find_category_item_collection(id)
      self.category_item_collections.find { |category_items| category_items.id == id }
    end

    class CategoryItemCollection < T::Struct
      class Item < T::Struct
        const :button_class, T.nilable(String)
        const :badge, T.nilable(String)
        const :button_link, T.nilable(String)
        const :description, T.nilable(String)
        const :title, T.nilable(String)
        const :feature_flag, T.nilable(String)
        const :not_feature_flag, T.nilable(String)
      end

      const :id, String
      const :items, T::Array[Item]
    end
  end
end
