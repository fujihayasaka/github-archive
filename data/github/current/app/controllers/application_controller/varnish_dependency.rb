# typed: false
# frozen_string_literal: true

#
# Helpers for getting dynamic content into cached pages.

module ApplicationController::VarnishDependency
  # Alternative to 'flash' for displaying messages in app/views/shared/_flash.html.erb.
  #
  # You should definitely use this if your code runs during a non-GET
  # request for logged out users and you redirect at the end.
  #
  # Do not use this in place of `flash.now`.
  def anonymous_flash
    @anonymous_flash ||= AnonymousFlash.new(cookies: cookies, cookie_domain: cookie_domain, request: request)
  end

  # Internal. Quacks a little bit like Rails's flash.
  class AnonymousFlash
    def initialize(cookies:, cookie_domain:, request:)
      @cookies = cookies
      @cookie_domain = cookie_domain
      @request = request
    end

    attr_reader :cookies, :cookie_domain, :request

    # Set a cookie that app/views/shared/_flash.html.erb + app/assets/modules/github/flash know how to display.
    #
    # Only notice, message, warn, error are valid types. Any others will raise.
    # The valid keys are defined in a few places:
    # * ApplicationHelper::ALLOWED_FLASH_KEYS
    # * app/assets/modules/github/flash.ts's ALLOWED_FLASH_KEYS
    # * ApplicationController::CookiesDependency::ANONYMOUS_COOKIES
    # * config/initializers/security_headers.rb's httponly exceptions
    def []=(type, message)
      return if message.blank?
      cookies["flash-#{type}"] = { value: Base64.strict_encode64(message),
                                   expires: 2.minutes.from_now, secure: request && request.ssl?, domain: cookie_domain }
    end

    def update(messages)
      messages.each do |k, v|
        self[k] = v
      end
    end
  end
end
