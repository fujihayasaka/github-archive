# typed: true
# frozen_string_literal: true

class SyncMarketplaceSearchIndexJob < ApplicationJob
  queue_as :marketplace
  schedule interval: 24.hours, condition: -> { !GitHub.enterprise? }

  def perform
    Marketplace::Listing.publicly_listed.find_each do |listing|
      listing.synchronize_search_index
    end
  end
end
