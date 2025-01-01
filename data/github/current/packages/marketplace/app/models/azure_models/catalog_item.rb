# typed: true
# frozen_string_literal: true

class AzureModels::CatalogItem < ApplicationRecord::Domain::Integrations # rubocop:todo GitHub/DatabaseModelsShouldHaveTests
  include GitHub::Memoizer

  self.table_name = "azure_models_catalog_items"

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
end
