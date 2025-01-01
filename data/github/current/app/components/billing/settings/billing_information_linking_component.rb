# typed: true
# frozen_string_literal: true
module Billing
  module Settings
    class BillingInformationLinkingComponent < ApplicationComponent
      attr_reader :actor, :target, :display_title, :form_loaded_from, :no_redirect, :return_to_path, :autocheck_link_checkbox, :wrapper_class, :include_form_tag

      def initialize(actor:,
                     target:,
                     display_title: true,
                     form_loaded_from: "NEW_FLOW",
                     no_redirect: false,
                     return_to_path: nil,
                     autocheck_link_checkbox: false,
                     include_form_tag: true,
                     wrapper_class: "")
        @actor = actor
        @target = target
        @display_title = display_title
        @form_loaded_from = form_loaded_from
        @no_redirect = no_redirect
        @return_to_path = return_to_path
        @autocheck_link_checkbox = autocheck_link_checkbox
        @include_form_tag = include_form_tag
        @wrapper_class = wrapper_class
      end

      def render?
        target.org_is_on_standard_tos?
      end

      memoize def show_unlink_button?
        return false if target.upcoming_charges?
        return false unless target.org_is_on_standard_tos?
        return false if user_can_update_billing_info_on_same_page?

        target.has_linked_trade_screening_record?
      end

      memoize def show_edit_button?
        return false unless org_account_is_linked_to_current_owner?
        return false if user_can_update_billing_info_on_same_page?

        !actor_is_restricted?
      end

      def show_edit_and_unlink_buttons?
        show_unlink_button? || show_edit_button?
      end

      # Does the org already have a linked screening profile? If we are trying to link a new one just
      # return false and continue as if the org doesn't have one linked.
      memoize def org_has_screening_record_linked?
        return false if link_other?

        target.has_linked_trade_screening_record?
      end

      memoize def actor_has_saved_screening_record?
        actor.has_saved_trade_screening_record?
      end

      def display_title?
        display_title
      end

      def include_form_tag?
        @include_form_tag
      end

      # The Blue info bubble with the "learn more" link.
      def display_info_flash?
        return false if actor_is_restricted?

        !org_has_screening_record_linked?
      end

      # The message and link to update your info if you do not have any.
      def display_update_link?
        return false if actor_is_restricted?
        return false if no_redirect && !org_account_is_linked_to_another_owner?

        !actor_has_saved_screening_record?
      end

      def user_can_create_billing_info_on_same_page?
        return false if actor_is_restricted?

        no_redirect && !actor_has_saved_screening_record?
      end

      def user_can_update_billing_info_on_same_page?
        return false if actor_is_restricted?

        no_redirect && actor_has_saved_screening_record?
      end

      def user_can_link_their_own_billing_info?
        return false if actor_is_restricted?(feature_type: :default)

        actor_has_saved_screening_record?
      end

      def hide_data_collection_form?
        return true if org_account_is_linked_to_another_owner?

        !user_can_create_billing_info_on_same_page?
      end

      # The message and link allowing a user to link their own record.
      # Displayed when the org does not already have a linked record
      def display_linking_option?
        return false if actor_is_restricted?

        !org_has_screening_record_linked? && actor_has_saved_screening_record?
      end

      memoize def org_account_is_linked_to_another_owner?
        org_has_screening_record_linked? && !actor_is_linked_to_org?
      end

      def org_account_is_linked_to_current_owner?
        org_has_screening_record_linked? && actor_is_linked_to_org?
      end

      # Is the current user trying to link their own account?
      # This is true when the org already has a linked record, and the current user is not the owner.
      def link_other?
        params[:link_other].present?
      end

      # The path for when another user wishes to link their billing information.
      def link_other_path
        settings_org_billing_tab_path(target, tab: "payment_information", link_other: true)
      end

      # The path for the linking controller at orgs/billing_settings/profile_linking_controller.rb.
      def submit_linking_path
        billing_information_linking_path(target)
      end

      memoize def org_trade_screening_record
        target.linked_trade_screening_record
      end

      memoize def actor_trade_screening_record
        actor.trade_screening_record
      end

      memoize def actor_is_linked_to_org?
        actor.has_trade_screening_record_linked_to_org?(organization: target)
      end

      def actor_is_restricted?(feature_type: :update_info)
        actor.has_trade_screening_restriction?(feature_type: feature_type)
      end

      # The link for a user's own billing information settings.
      def actor_billing_information_link
        settings_user_billing_tab_path(tab: "payment_information", return_to: request&.fullpath)
      end

      def render_billing_info_inputs(url_for: nil, method: :post, include_form_tag: true, &block)
        if include_form_tag
          form_tag(url_for, method: method, &block)
        else
          capture(&block)
        end
      end
    end
  end
end
