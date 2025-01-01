# typed: true
# frozen_string_literal: true

module Repositories
  module Settings
    module Deletions
      class WarningComponent < ApplicationComponent
        CODESPACES_DOTFILES_DOCS_URL = "https://docs.github.com/codespaces/customizing-your-"\
          "codespace/personalizing-github-codespaces-for-your-account#dotfiles"
        WARNING_ALERT = "Unexpected bad things will happen if you don’t read this!"

        def initialize(repository:, stage:)
          @repository = repository
          @stage = stage
        end

        private

        attr_reader :repository, :stage

        delegate :is_codespace_dotfiles_repo?, to: :helpers

        def warning_message
          if stage == 2
            detailed_warning_message
          end
        end

        def detailed_warning_message
          safe_join([
            tag.hr,
            main_warning_message,
            content_tag(:div, class: "mt-2") do
              safe_join([
                permanent_delete_message,
                org_discussions_message,
                forks_message,
                billing_message,
                codespaces_message,
              ].compact)
            end,
          ])
        end

        def codespaces_message
          return unless is_codespace_dotfiles_repo?(current_user, repository)

          build_display_message(
            safe_join([
              "This is a ",
              link_to("dotfiles repository", CODESPACES_DOTFILES_DOCS_URL),
              ". If you delete it, you will need to re-enable dotfiles in your Codespaces Settings.",
            ]),
          )
        end

        def billing_message
          return unless repository.private? && GitHub.billing_enabled?

          build_display_message(
            "This will not change your billing plan. If you want to downgrade, you can do so in "\
              "your Billing Settings.",
          )
        end

        def forks_message
          return unless repository.private? && dependent_fork_count > 0

          build_display_message(
            safe_join([
              "This will also delete ",
              content_tag(:strong, pluralized_fork_count),
              " since this is a private repository.",
            ]),
          )
        end

        def pluralized_fork_count
          modifier = dependent_fork_count > 1 ? "all " : nil

          safe_join([
            modifier,
            pluralize(number_with_delimiter(dependent_fork_count), "fork"),
          ].compact)
        end

        memoize def dependent_fork_count
          repository.repository_and_dependents.size - 1
        end

        def org_discussions_message
          return unless repository.organization_discussion.present?

          build_display_message(
            safe_join([
              "Deleting this repository will disable ",
              repository.public? ? "public " : "member ",
              "organization discussions for ",
              content_tag(:strong, repository.owner.name),
            ]),
          )
        end

        def permanent_delete_message
          build_display_message(
            safe_join([
              "This will permanently delete the ",
              content_tag(:strong, repository.name_with_display_owner),
              " repository, wiki, issues, comments, ",
              !GitHub.enterprise? ? "packages, " : nil,
              GitHub.actions_enabled? ? "secrets, workflow runs, " : nil,
              "and remove all ",
              repository.in_organization? ? "team " : "collaborator ",
              "associations.",
            ].compact),
          )
        end

        def build_display_message(message)
          render(Primer::Beta::TimelineItem.new(
            p: 0,
            condensed: true,
            classes: "repository-delete-warning",
          )) do |component|
            component.with_badge(bg: :transparent, color: :subtle, icon: :"dot-fill")
            component.with_body.with_content(message)
          end
        end

        def main_warning_message
          safe_join([
            content_tag(:div, class: "flash mt-3 flash-warn") do
              safe_join([primer_octicon(:alert), WARNING_ALERT])
            end
          ])
        end
      end
    end
  end
end
