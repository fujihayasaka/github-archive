# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class MarketplaceOauthAppInstallJob < ApplicationJob
  queue_as :marketplace
  retry_on_dirty_exit

  def perform(user:, application:)
    Marketplace::RecordMarketplaceInstallation.call(user: user, application: application)
  end
end
