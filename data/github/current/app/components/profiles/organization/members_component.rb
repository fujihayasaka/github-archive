# typed: true
# frozen_string_literal: true

module Profiles
  module Organization
    class MembersComponent < ApplicationComponent
      include Orgs::Invitations::RateLimiting

      MEMBERS_LIMIT = 20

      def initialize(profile_layout_data:)
        @profile_layout_data = profile_layout_data
      end

      private

      attr_reader :profile_layout_data

      delegate(
        :profile_organization,
        :adminable_by_viewer?,
        to: :profile_layout_data,
      )

      delegate(
        :avatar_for,
        :more_seats_link_for_organization,
        :create_view_model,
        to: :helpers,
      )

      def invite_cta
        helpers.invite_or_add_action_word(enterprise_managed: profile_organization&.enterprise_managed_user_enabled?)
      end

      def org_at_seat_limit?
        profile_organization.at_seat_limit?
      end

      def per_seat_pricing_model
        Billing::PlanChange::PerSeatPricingModel.new \
          profile_organization,
          seats: profile_organization.seats,
          plan_duration: profile_organization.plan_duration,
          new_plan: profile_organization.plan
      end

      def multi_invite_view_model
        create_view_model(
          Orgs::Invitations::InviteFormView,
          organization: profile_organization,
          per_seat_pricing_model: per_seat_pricing_model,
          rate_limited: rate_limited,
        )
      end

      def rate_limited
        org_invite_rate_limited?
      end

      def invite_rate_limited_organization
        profile_organization
      end

      def organization_members
        profile_layout_data.organization_members.limit(MEMBERS_LIMIT)
      end

      def more_items?
        profile_layout_data.organization_members.count > MEMBERS_LIMIT
      end

      def organization_member_url(member)
        if adminable_by_viewer?
          org_person_path(profile_organization, member)
        else
          user_path(member)
        end
      end

      def show_buy_more_seats_link?
        return true unless profile_organization&.business.present?
        return false if profile_organization.business.downgraded_to_free_plan?
        return false if profile_organization.business.dunning?
        true
      end
    end
  end
end
