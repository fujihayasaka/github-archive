# typed: true
# frozen_string_literal: true

class MarketplaceCategoriesRepositoryAction < ApplicationRecord::Domain::Repositories
  belongs_to :repository_action, class_name: "RepositoryAction"
  belongs_to :marketplace_category, class_name: "Marketplace::Category"
end
