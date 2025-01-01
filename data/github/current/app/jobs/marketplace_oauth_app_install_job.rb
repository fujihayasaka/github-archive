# typed: true
# frozen_string_literal: true

class MarketplaceOauthAppInstallJob < ApplicationJob
  queue_as :marketplace

  def perform(user:, application:)
    Marketplace::RecordMarketplaceInstallation.call(user: user, application: application)
  end
end
