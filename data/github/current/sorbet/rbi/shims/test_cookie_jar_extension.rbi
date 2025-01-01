# typed: strict
# frozen_string_literal: true

module CookieJarExtension
  sig { params(raw_cookies: String, uri: T.nilable(String)).void }
  def merge(raw_cookies, uri = nil); end
end
