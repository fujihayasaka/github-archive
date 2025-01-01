# typed: true
# frozen_string_literal: true

module Stafftools
  module RepositoryViews
    class PagesHTTPSStatusView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      PAGES_CERTIFICATES_PROJECT_ID = 1890346

      include Stafftools::Sentry
      extend Forwardable

      attr_reader :page
      attr_reader :current_repository

      def_delegator :page, :cname?, :cname?
      def_delegator :page, :cname, :cname
      def_delegator :page, :https_redirect?, :https_redirect?
      def_delegator :page, :https_available?, :https_available?
      def_delegator :page, :certificate, :certificate

      def certificates_enabled?
        GitHub.pages_custom_domain_https_enabled?
      end

      def eligible_for_certificate?
        return true if certificate&.needs_renewal?
        return false if certificate&.usable?
        page&.eligible_for_certificate?
      end

      private

      def certificate_id
        page&.certificate&.id
      end
    end
  end
end
