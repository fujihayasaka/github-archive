# typed: true
# frozen_string_literal: true

module Notifyd
  module NotifydFailbot
    def self.report(error, extra = {})
      Failbot.report(error, extra.merge(app: "github-notifyd", catalog_service: "github/notifications"))
    end

    def self.report!(error, extra = {})
      Failbot.report!(error, extra.merge(app: "github-notifyd", catalog_service: "github/notifications"))
    end
  end
end
