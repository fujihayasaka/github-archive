# typed: false
# frozen_string_literal: true

module Asset::AlambicCaller
  extend T::Helpers

  def self.included(model)
    model.extend ClassMethods
  end

  def http
    self.class.http
  end

  module ClassMethods
    def alambic_http(...)
      # We use a timeout of 180 seconds to ensure we allow enough time for
      # AWS S3 to copy large LFS objects, which may be up to 5 GB in size.
      # These PUT requests can exceed the default 60 second timeout provided
      # by Net::HTTP.  By setting the generic timeout value for the Faraday
      # connection, Faraday 0.17.x will use that to initialize the Net::HTTP
      # read timeout.
      Faraday.new(url: GitHub.alambic_url, request: { timeout: 180 }) do |b|
        b.adapter(...)
      end
    end

    def stub_http(&block)
      @http = alambic_http(:test, &block)
    end

    def reset_http!
      @http = nil
    end

    def http
      @http ||= alambic_http(Faraday.default_adapter)
    end
  end

  mixes_in_class_methods(ClassMethods)
end
