# typed: true
# frozen_string_literal: true

module NotificationsFailbot
  def self.report(error, extra = {})
    Failbot.report(error, extra.merge(app: "github-notifications-maintenance"))
  end

  def self.report!(error, extra = {})
    Failbot.report!(error, extra.merge(app: "github-notifications-maintenance"))
  end
end
