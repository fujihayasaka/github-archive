# typed: true
# frozen_string_literal: true

require "delegate"
require "set"

module GitHub
  class AllowlistedCookieJar < Delegator
    class Error < StandardError; end

    attr_reader :__cookies__, :__keys__
    alias_method :__getobj__, :__cookies__

    def initialize(cookies, keys = Set.new)
      @__cookies__ = cookies
      @__keys__    = keys
    end

    def [](key)
      if !__keys__.include?(key.to_sym) && GitHub.cookie_allowlist_enforced?
        Kernel.raise Error, "attempt to read disallowed cookie name: #{key.inspect}"
      end

      __cookies__[key]
    end

    def []=(key, options)
      if !__keys__.include?(key.to_sym) && GitHub.cookie_allowlist_enforced?
        Kernel.raise Error, "attempt to write disallowed cookie name: #{key.inspect}"
      end

      __cookies__[key] = options
    end
  end
end
