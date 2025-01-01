# typed: true
# frozen_string_literal: true

module Mocks
  module GitHub
    def cache
      @cache ||= TestCacheStorage.new
    end

    def cache=(cache)
      @cache = cache
    end

    def flipper
      @flipper ||= Flipper.new
    end

    def open_exchange_rates_app_id
      "THE API KEY"
    end

    def enterprise?
      false
    end

    def billing_enabled?
      true
    end
  end
end
