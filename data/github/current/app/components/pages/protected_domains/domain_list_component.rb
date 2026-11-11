# typed: true
# frozen_string_literal: true

module Pages
  module ProtectedDomains
    class DomainListComponent < ApplicationComponent
      attr_reader :domains, :owner

      def initialize(domains:, owner:)
        @domains = domains
        @owner = owner
      end

      def no_domains_message
        if owner.organization?
          "There are no verified domains for this organization."
        else
          "There are no verified domains."
        end
      end
    end
  end
end
