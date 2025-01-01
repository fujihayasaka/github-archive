# typed: true
# frozen_string_literal: true

module GitHub
  module CacheLeakDetector
    include Kernel
    class CacheLeak < StandardError; end

    # Raise or report an exception if we're in a caching block.
    #
    # Returns nothing. Raises GitHub::CacheLeakDetector::CacheLeak.
    def no_caching!
      if ActionView::Helpers::CacheHelper::CachingRegistry.caching?
        error = CacheLeak.new "sensitive information rendered in cache block"
        error.set_backtrace(caller)
        if Rails.env.test? || Rails.env.development?
          raise error
        else
          Failbot.report(error)
        end
      end
    end

    extend self
  end
end
