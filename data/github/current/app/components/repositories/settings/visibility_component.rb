# typed: true
# frozen_string_literal: true

module Repositories
  module Settings
    class VisibilityComponent < ApplicationComponent
      include SettingsHelper
      include FeatureGateHelper

      def initialize(repository:)
        @repository = repository
      end

      private

      attr_reader :repository

      def disable_button?
        repository.fork? || public_repo_with_trade_restrictions?
      end

      def can_change_visibility?
        members_can_change_visibility? && owner_can_privatize? && available_visibilities.size >= 1
      end

      memoize def current_visibility
        repository.visibility
      end

      memoize def plan_owner
        repository.plan_owner
      end

      memoize def available_visibilities
        if !owner_can_privatize?
          [
            current_visibility, # Could be internal or private
            ::Repository::PUBLIC_VISIBILITY,
          ]
        elsif repository.owner&.business
          [
            ::Repository::PUBLIC_VISIBILITY,
            ::Repository::PRIVATE_VISIBILITY,
            ::Repository::INTERNAL_VISIBILITY,
          ]
        else
          [
            ::Repository::PUBLIC_VISIBILITY,
            ::Repository::PRIVATE_VISIBILITY,
          ]
        end.tap do |visibilities|
          visibilities.delete(::Repository::PUBLIC_VISIBILITY) if repository.is_enterprise_managed?
          visibilities.delete(::Repository::PUBLIC_VISIBILITY) if !repo_policy_bypass_enabled? && !can_change_visibility_with_rules?("public")
          visibilities.delete(::Repository::INTERNAL_VISIBILITY) if !repo_policy_bypass_enabled? && !can_change_visibility_with_rules?("internal")
          visibilities.delete(::Repository::PRIVATE_VISIBILITY) if !repo_policy_bypass_enabled? && !can_change_visibility_with_rules?("private")
        end
      end

      sig { returns(T::Boolean) }
      def repo_policy_bypass_enabled?
        repository.repo_policy_bypass_enabled?
      end

      sig { returns(T::Boolean) }
      def can_request_bypass?
        repo_policy_bypass_enabled? && cant_change_some_visibilities_with_rules?
      end

      def bypass_form_path
        repository_request_bypass_path(
          repository: repository.name,
          user_id: repository.owner_display_login,
          action_type: "change_visibility"
        )
      end

      def can_change_visibility_with_rules?(visibility)
        repository.can_change_repo_visibility_with_rules?(current_user, visibility)
      end

      memoize def cant_change_some_visibilities_with_rules?
        !can_change_visibility_with_rules?("private") || !can_change_visibility_with_rules?("internal") || !can_change_visibility_with_rules?("public")
      end

      def name_of_ruleset_source_blocking_visibility(visiblity)
        RulesEngine::RepositoryActionEvaluator.name_of_ruleset_source_blocking_visibility(repository, current_user, visiblity, persist_results: false)
      end

      memoize def members_can_change_visibility?
        repository.can_change_repo_visibility?(current_user)
      end

      memoize def owner_can_privatize?
        repository.can_privatize?
      end

      memoize def public_repo_with_trade_restrictions?
        repository.public? && repository.has_any_trade_restrictions?
      end

      def description
        if repository.fork?
          "For security reasons, you cannot change the visibility of a fork."
        elsif public_repo_with_trade_restrictions?
          TradeControls::Notices.generic_prevent_toggle_to_private(type: "repository")
        elsif !members_can_change_visibility?
          "Organization members can’t change repo visibility."
        elsif cant_change_some_visibilities_with_rules?
          "Ruleset(s) are restricting how this repo's visibility can be changed."
        elsif owner_can_privatize?
          default_description
        elsif !plan_owner.organization?
          upgrade_user_plan_description
        elsif !plan_owner.adminable_by?(current_user) && repository.adminable_by?(current_user)
          ask_owner_to_upgrade_description
        elsif !plan_owner.plan.per_seat?
          upgrade_org_plan_description
        elsif !repository.owner_has_seats_for_collaborators?
          add_seats_description
        elsif !repository.owner_has_seats_for_collaborators?(pending_cycle: true)
          cancel_downgrade_description
        else
          default_description
        end
      end

      def default_description
        "This repository is currently #{current_visibility}."
      end

      def upgrade_user_plan_description
        safe_join([
          "Please ",
          link_to("upgrade your plan", settings_user_billing_path, data: feature_gate_upsell_click_attrs),
          " to change this repository's visibility."
        ])
      end

      def ask_owner_to_upgrade_description
        upgrade_text = plan_owner.plan.per_seat? ? "add seats to" : "upgrade"
        "Please ask one of the owners to #{upgrade_text} #{plan_owner} if you want to change this repository's visibility."
      end

      def upgrade_org_plan_description
        safe_join([
          "Please ",
          link_to(
            "upgrade #{plan_owner}",
            settings_org_billing_path(plan_owner),
            data: feature_gate_upsell_click_attrs,
          ),
          "."
        ])
      end

      def add_seats_description
        seats_needed = plan_owner.seats_needed_for_collaborators_on(repository)
        link_url = org_seats_path(plan_owner, seats: seats_needed, return_to: edit_repository_path(repository))
        link_copy = "add #{seats_needed} #{"seat".pluralize(seats_needed)} to #{plan_owner}"

        safe_join([
          "Please ",
          link_to(link_copy, link_url, data: feature_gate_upsell_click_attrs("collaborators")),
          " to change this repository's visibility.",
        ])
      end

      def cancel_downgrade_description
        confirm_message = "Are you sure you want to cancel these pending plan changes?"

        form_tag(update_pending_plan_change_path(plan_owner), method: :put) do
          hidden_field_tag(:cancel_seats, true)
          safe_join([
            "Please ",
            button_tag("cancel the pending seat downgrade", class: "btn-link", data: { confirm: confirm_message }),
            " to ensure there are seats for collaborators to change this repository's visibility."
          ])
        end
      end
    end
  end
end
