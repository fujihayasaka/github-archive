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
            caption: first_time_contributor_new_users_caption,
            checked: effective_policy == Configurable::ActionsForkPrApprovals::FIRST_TIME_CONTRIBUTOR_NEW_USERS
          )

          approvals_group.radio_button(
            label: "Require approval for first-time contributors",
            value: Configurable::ActionsForkPrApprovals::FIRST_TIME_CONTRIBUTORS,
            caption: first_time_contributors_caption,
            checked: effective_policy == Configurable::ActionsForkPrApprovals::FIRST_TIME_CONTRIBUTORS
          )

          approvals_group.radio_button(
            label: "Require approval for all external contributors",
            value: Configurable::ActionsForkPrApprovals::ALL_OUTSIDE_COLLABORATORS,
            description: all_outside_collaborators_description,
            caption: all_outside_collaborators_caption,
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

      def initialize(entity:, action:, use_new_copy:)
        @entity = entity
        @action = action
        @use_new_copy = use_new_copy
      end

      private

      def effective_policy
        @_effective_policy ||= @entity.actions_fork_pr_approvals_policy
      end

      def first_time_contributor_new_users_caption
        return "Only first-time contributors who recently created a GitHub account will require approval to run workflows." unless @use_new_copy

        "Only users who are both new on GitHub and who have never had a commit or pull request merged into this repository will require approval to run workflows."
      end

      def first_time_contributors_caption
        return "Only first-time contributors will require approval to run workflows." unless @use_new_copy

        "Only users who have never had a commit or pull request merged into this repository will require approval to run workflows."
      end

      def all_outside_collaborators_description
        return nil if @use_new_copy

        "All outside collaborators will always require approval to run workflows on their pull requests."
      end

      def all_outside_collaborators_caption
        return nil unless @use_new_copy

        if @entity.is_a?(Repository)
          if @entity.organization.present?
            "All users that are not a member or owner of this repository and not a member of the #{@entity.organization.display_login} organization will require approval to run workflows."
          else
            "All users that are not a member or owner of this repository will require approval to run workflows."
          end
        elsif @entity.is_a?(Organization)
          "All users that are not a member or owner of the repository and not a member of the #{@entity.display_login} organization will require approval to run workflows."
        else
          "All users that are not a member or owner of the repository and not a member of the organization will require approval to run workflows."
        end
      end
    end
  end
end
