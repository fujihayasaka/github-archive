# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class ViaAppComponent < ApplicationComponent

    attr_reader :app

    def initialize(app:)
      @app = app
    end

    memoize def html_url
      Addressable::URI.parse("#{GitHub.url}/#{app.bot.to_param}").to_s
    end

    memoize def logo_url
      app.preferred_avatar_url(size: 40)
    end
  end
end
