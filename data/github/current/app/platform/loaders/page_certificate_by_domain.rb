# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class PageCertificateByDomain < Platform::Loader
      def self.load(domain)
        self.for.load(domain)
      end

      def self.load_all(domains)
        loader = self.for
        Promise.all(domains.map { |domain| loader.load(domain) })
      end

      def fetch(domains)
        Page::Certificate.where(domain: domains).index_by(&:domain)
      end
    end
  end
end
