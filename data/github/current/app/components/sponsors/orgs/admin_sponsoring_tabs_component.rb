# typed: true
# frozen_string_literal: true

module Sponsors
  module Orgs
    class AdminSponsoringTabsComponent < ApplicationComponent
      # org - an Organization
      # selected_link - a Symbol representing the active tab
      # viewer_can_manage_sponsorships - optional Boolean if already known for whether the currently authenticated user
      #                                 has permission to manage the sponsorships for the given org
      def initialize(org:, selected_link:, viewer_can_manage_sponsorships: false)
        @org = org
        @selected_link = selected_link
        @viewer_can_manage_sponsorships = viewer_can_manage_sponsorships
      end

      private

      attr_reader :selected_link, :org

      def render?
        return false unless org && GitHub.sponsors_enabled? && logged_in?
        viewer_can_manage_sponsorships? || staff_view_for_invoiced_sponsor?
      end

      def viewer_can_manage_sponsorships?
        @viewer_can_manage_sponsorships
      end

      def staff_view_for_invoiced_sponsor?
        current_user.can_admin_sponsors_listings? && org.sponsors_invoiced?
      end

      def show_invoices_tab?
        return false unless org.sponsors_insights_accessible_by?(current_user)
        org.sponsors_customer_account.present?
      end

      def show_settings_tab?
        org.adminable_by?(current_user)
      end
    end
  end
end
