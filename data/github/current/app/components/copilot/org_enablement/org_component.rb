# typed: strict
# frozen_string_literal: true

module Copilot
  module OrgEnablement
    class OrgComponent < ApplicationComponent

      MenuItemProps = T.type_alias do
        {
          enablement_status: String,
          title: String,
          text: String,
          data: T::Hash[Symbol, String],
          classes: String
        }
      end

      delegate :linked_avatar_for, to: :helpers

      sig { params(business: ::Business, organization: ::Organization, feature_requests: T::Hash[T.untyped, T.untyped], show_check: T::Boolean).void }
      def initialize(business:, organization:, feature_requests: {}, show_check: false)
        @business = business
        @organization = organization
        @show_check = show_check
        @copilot_business = T.let(Copilot::Business.new(@business), Copilot::Business)
        @feature_requests = feature_requests
      end

      sig { returns(String) }
      def feature_requests_label
        return "" if @feature_requests.nil?
        return "" if enablement_status == "enabled"

        admins_requests = @feature_requests[:admins] > 0 ? "#{@feature_requests[:admins]} #{"admin".pluralize(@feature_requests[:admins])}" : ""
        members_requests = @feature_requests[:members] > 0 ? "#{@feature_requests[:members]} #{"member".pluralize(@feature_requests[:members])}" : ""

        requests = if admins_requests.present? && members_requests.present?
          "#{admins_requests} + #{members_requests}"
        elsif admins_requests.present?
          admins_requests
        else
          members_requests
        end

        requests
      end

      sig { returns(String) }
      def avatar_stack_classes
        "AvatarStack flex-self-start #{avatar_stack_count_class(@feature_requests[:requesters].count)}"
      end

      sig { returns(T::Boolean) }
      def show_enable_access_button?
        copilot_organization.copilot_disabled? && @copilot_business.copilot_enabled_for_selected_organizations?
      end

      sig { returns(T::Boolean) }
      def is_reenable_access_request?
        show_enable_access_button? && has_seat_assignments?
      end

      sig { returns(T::Boolean) }
      memoize def has_seat_assignments?
        Copilot::SeatAssignment.for_organization(@organization).organization_assignments.any?
      end

      private

      sig { returns(String) }
      memoize def menu_item_classes
        base_classes = "SelectMenu-item"
        return base_classes if copilot_organization.copilot_enabled? || is_reenable_access_request?

        base_classes + " js-copilot-update-individual-org-enablement"
      end

      sig { returns(T::Array[MenuItemProps]) }
      memoize def menu_items
        copilot_enabled = copilot_organization.copilot_enabled?
        data = (copilot_enabled || is_reenable_access_request?) ? { action: "click:copilot-mixed-license-orgs-list#handleShowModal" } : {}
        data[:reenable] = true if is_reenable_access_request?

        items = [
          {
            enablement_status: "business",
            title: "Business",
            text: is_plan_downgrading? ? "The activation of the Business plan for the organization has been scheduled." : "Organization can issue Business licences to users.",
            data: data.merge({ value: "business", "org-id": @organization.id, confirm: "Please confirm if you wish to grant this organization the ability to issue business licenses. A downgrade will be scheduled if applicable." }),
            classes: menu_item_classes
          },
          {
            enablement_status: "enterprise",
            title: "Enterprise",
            text: "Organization can issue Enterprise licences to users.",
            data: data.merge({ value: "enterprise", "org-id": @organization.id, confirm: "Please confirm if you wish to grant this organization the ability to issue enterprise licenses. Licenses within the selected organization will be converted to Copilot Enterprise ($39 / user per month)." }),
            classes: menu_item_classes
          }
        ]

        if @copilot_business.copilot_enabled_for_selected_organizations? && copilot_enabled
          items << {
            enablement_status: "disabled",
            title: "Remove access",
            text: "Disable access to Copilot for the organization.",
            data: data.merge({ value: "disable", "org-id": @organization.id }),
            classes: menu_item_classes
          }
        end

        items
      end

      sig { returns(T.nilable(Copilot::Configuration)) }
      memoize def org_configuration
        Copilot::Configuration.find_by(configurable_id: copilot_organization.id, configurable_type: "Organization")
      end

      sig { returns(String) }
      def enablement_status
        return copilot_organization.copilot_plan if copilot_organization.copilot_enabled?

        "disabled"
      end

      sig { returns(Copilot::Organization) }
      memoize def copilot_organization
        Copilot::Organization.new(@organization)
      end

      sig { returns(T::Boolean) }
      def allow_selections?
        @copilot_business.copilot_enabled_for_selected_organizations?
      end

      sig { returns(T::Boolean) }
      def select_disabled?
        is_trial_org? || copilot_organization.copilot_disabled?
      end

      sig { params(item: T::Hash[Symbol, T.any(String, T::Hash[Symbol, String])]).returns(T::Boolean) }
      def is_selected?(item)
        enablement_status == item[:enablement_status]
      end

      sig { params(item: T::Hash[Symbol, T.any(String, T::Hash[Symbol, String])]).returns(T::Boolean) }
      def option_disabled?(item)
        data = T.cast(item[:data], T::Hash[Symbol, String])
        (is_plan_downgrading? && data[:value] == "business") || is_selected?(item)
      end

      sig { returns(T::Boolean) }
      def is_plan_downgrading?
        copilot_organization.pending_plan_downgrade_date.present?
      end

      sig { returns(T::Boolean) }
      memoize def is_trial_org?
        !!business_trial&.has_trial?
      end

      sig { returns(T.nilable(Copilot::BusinessTrial)) }
      memoize def business_trial
        copilot_organization.business_trial
      end

      sig { returns(Integer) }
      memoize def seat_count
        Copilot::Seat.for_organization(@organization).count
      end

      sig { returns(String) }
      def scheduled_downgrade_message
        return " Your Copilot access will be disabled on #{copilot_organization.pending_plan_downgrade_date.strftime('%d %B %Y')}" if copilot_organization.copilot_disabled?
        " Business plan will be active on #{copilot_organization.pending_plan_downgrade_date.strftime('%d %B %Y')}"
      end

      sig { returns(String) }
      def trial_org_status_message
        return "" if business_trial.nil?

        trial = T.must(business_trial)

        return "Organization awaiting  #{trial.copilot_plan.capitalize} trial activation" if trial.pending?

        "Organization is on a #{trial.copilot_plan.capitalize} trial until #{trial.ends_at.strftime("%d %B %Y")}"
      end
    end
  end
end
