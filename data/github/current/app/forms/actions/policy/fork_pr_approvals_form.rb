# typed: false
# frozen_string_literal: true

module Actions
  module Policy
    class ForkPrApprovalsForm < ApplicationForm
      form do |approvals_form|
        approvals_form.radio_button_group(name: :actions_fork_pr_approvals, label: nil) do |approvals_group|
          approvals_group.radio_button(
            label: "Require approval for first-time contributors who are new to GitHub",
            value: Configurable::ActionsForkPrApprovals::FIRST_TIME_CONTRIBUTOR_NEW_USERS,
            caption: "Only first-time contributors who recently created a GitHub account will require approval to run workflows.",
            checked: effective_policy == Configurable::ActionsForkPrApprovals::FIRST_TIME_CONTRIBUTOR_NEW_USERS
          )

          approvals_group.radio_button(
            label: "Require approval for first-time contributors",
            value: Configurable::ActionsForkPrApprovals::FIRST_TIME_CONTRIBUTORS,
            caption: "Only first-time contributors will require approval to run workflows.",
            checked: effective_policy == Configurable::ActionsForkPrApprovals::FIRST_TIME_CONTRIBUTORS
          )

          approvals_group.radio_button(
            label: "Require approval for all outside collaborators",
            value: Configurable::ActionsForkPrApprovals::ALL_OUTSIDE_COLLABORATORS,
            description: "All outside collaborators will always require approval to run workflows on their pull requests.",
            checked: effective_policy == Configurable::ActionsForkPrApprovals::ALL_OUTSIDE_COLLABORATORS
          )
        end

        approvals_form.submit(
          name: :submit,
          label: "Save",
          aria: {
            label: "Save fork pull request workflows setting"
          }
        )
      end

      def initialize(entity:, action:)
        @entity = entity
        @action = action
      end

      private

      def effective_policy
        @_effective_policy ||= @entity.actions_fork_pr_approvals_policy
      end
    end
  end
end
