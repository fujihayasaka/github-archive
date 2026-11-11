# typed: true
# frozen_string_literal: true

module NotificationsFailbot
  def self.report(error, extra = {})
    Failbot.report(error, extra.merge(app: "github-notifications-maintenance", catalog_service: "github/notifications"))
  end

  def self.report!(error, extra = {})
    Failbot.report!(error, extra.merge(app: "github-notifications-maintenance", catalog_service: "github/notifications"))
  end
end
