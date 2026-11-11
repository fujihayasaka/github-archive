# typed: true
# frozen_string_literal: true

module Pages
  module ProtectedDomains
    class DomainComponent < ApplicationComponent
      include PagesProtectedDomainsHelper
      include SettingsHelper

      attr_reader :domain

      def initialize(domain:)
        @domain = domain
      end

      def status_label_text
        case domain.state.to_s
        when "unverified"
          "Unverified"
        when "pending"
          "Needs reverification"
        when "verified"
          "Verified"
        end
      end

      def status_label_color
        case domain.state.to_s
        when "unverified"
          :danger
        when "pending"
          :warning
        when "verified"
          :success
        end
      end

      def status_note
        case domain.state.to_s
        when "unverified"
          "Please verify your domain"
        when "pending"
          if domain.unverified_at
            if domain.unverified_at - Time.zone.now <= 1.day
              "Please reverify your domain today"
            else
              "Please reverify your domain within #{time_until_unverification(domain.unverified_at)}"
            end
          else
            # A domain should never be in a state where it's pending but doesn't
            # have an unverified_at time
            "Please reverify your domain"
          end
        end
      end

      def name
        domain.name
      end

      def domain_name_slug
        return unless name.present?
        domain.name.gsub(".", "-")
      end

      def domain_path
        if domain.owner.organization?
          settings_org_pages_protected_domain_path(domain.owner, domain)
        else
          settings_pages_protected_domain_path(domain)
        end
      end
    end
  end
end
