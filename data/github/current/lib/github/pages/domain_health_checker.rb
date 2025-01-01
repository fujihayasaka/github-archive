# typed: true
# frozen_string_literal: true

require "github-pages-health-check"
require "github/timeout_and_measure"

module GitHub
  module Pages
    class DomainHealthChecker
      extend Forwardable
      include GitHub::TimeoutAndMeasure

      TIMEOUT = 5 # seconds

      attr_reader :domain

      def initialize(domain)
        @domain = domain
      end

      def check
        @check ||= ((run("valid") { checks.find(&:valid?) }) || check_with_default_nameservers)
      end

      def_delegator :check, :reason, :reason
      def_delegator :check, :valid?, :valid?

      def https_eligible?
        !!(run("https_eligible") { checks.any?(&:https_eligible?) })
      end

      private

      def checks
        @checks ||= GitHubPages::HealthCheck::RedundantCheck.new(domain).send(:checks)
      end

      def check_with_default_nameservers
        @check_with_default_nameservers ||= checks.find { |c| c.nameservers == :default }
      end

      def run(stat_name)
        timeout_and_measure(TIMEOUT, "pages.dns_check.#{stat_name}") { yield }
      end

    end
  end
end
