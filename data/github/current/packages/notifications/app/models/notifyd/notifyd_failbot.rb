# typed: true
# frozen_string_literal: true

module Notifyd
  module NotifydFailbot
    def self.report(error, extra = {})
      Failbot.report(error, extra.merge(app: "github-notifyd"))
    end

    def self.report!(error, extra = {})
      Failbot.report!(error, extra.merge(app: "github-notifyd"))
    end
  end
end
