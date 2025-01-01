# typed: true
# frozen_string_literal: true

class AzureModels::CatalogItem < ApplicationRecord::Domain::Integrations # rubocop:todo GitHub/DatabaseModelsShouldHaveTests
  include GitHub::Memoizer

  self.table_name = "azure_models_catalog_items"

  enum :visibility, {
    visible: 0,
    staffshipped: 1,
    hidden: 2,
  }

  # Public: Synchronize this action with its representation in the search
  # index. All existing actions that are not delisted get indexed.
  def synchronize_search_index(deleting: false)
    if deleting
      RemoveFromSearchIndexJob.perform_later("azure_model", self.id)
    else
      Search.add_to_search_index("azure_model", self.id)
    end

    self
  end

  memoize def parsed_value
    JSON.parse(value).deep_symbolize_keys
  end

  sig { params(user: T.nilable(User)).returns(T::Hash[String, T::Boolean]) }
  def self.visibility_map(user)
    AzureModels::CatalogItem.where.not(key: "all_models").each_with_object({}) do |item, hash|
      case item.visibility
      when "visible"
        hash[item.key] = true
      when "staffshipped"
        hash[item.key] = !!user&.employee?
      when "hidden"
        hash[item.key] = false
      end
    end
  end

  sig { params(user: T.nilable(User), registry: String, name: String).returns(T::Boolean) }
  def self.can_view?(user:, registry:, name:)
    catalog_item = AzureModels::CatalogItem.find_by(key: "#{registry}/#{name}")
    return false if catalog_item.nil?

    case catalog_item.visibility
    when "visible"
      true
    when "staffshipped"
      !!user&.employee?
    when "hidden"
      false
    end
  end
end
