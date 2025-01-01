# typed: true
# frozen_string_literal: true

module Repositories
  module Settings
    module Visibilities
      class WarningComponent < ApplicationComponent
        WARNING_ALERT = "Warning: this is a destructive action"
        WARNING_MESSAGES = {
          "private" => [
            "Making this repository private could permanently erase these counts by removing "\
              "stars and watchers associated to users that will no longer have access to this "\
              "repository:",
            "If you decide to make this repository public in the future, it will not be possible to "\
              "restore these stars and watchers and this will affect its repository rankings.",
            "Dependency graph and Dependabot alerts will remain enabled with permission to perform "\
              "read-only analysis on this repository. Any custom Dependabot alert rules will be disabled "\
               "unless GitHub Advanced Security is enabled for this repository.",
            "Code scanning will become unavailable.",
            "Current forks will remain public and will be detached from this repository.",
          ],
          "internal" => [
            "Making this repository internal could permanently erase these counts by removing "\
              "stars and watchers associated to users that will no longer have access to this "\
              "repository:",
            "All members of the enterprise will be given read access.",
            "Outside collaborators can no longer be added to forks unless they're added to the root.",
          ],
          "public" => [
            "",
            "The code will be visible to everyone who can visit %{github_url}",
            "Anyone can fork your repository.",
            "All push rulesets will be disabled.",
            "Your changes will be published as activity.",
            "Actions history and logs will be visible to everyone.",
          ],
        }.freeze

        def initialize(repository:, new_visibility:, stage:)
          @repository = repository
          @new_visibility = new_visibility
          @stage = stage
        end

        private

        attr_reader :repository, :new_visibility, :stage

        def stars_and_watchers
          content_tag(:div, class: "mb-3 text-center") do
            safe_join([
              content_tag(:span, class: "btn color-fg-danger cursor-default") do
                safe_join([
                  primer_octicon(:star, mr: 1, color: :danger),
                  helpers.number_with_delimiter(repository.stargazer_count),
                  content_tag(:span, "star".pluralize(repository.stargazer_count), class: "ml-1"),
                ])
              end,
              content_tag(:span, class: "btn color-fg-danger cursor-default ml-2") do
                safe_join([
                  primer_octicon(:eye, mr: 1, color: :danger),
                  helpers.number_with_delimiter(repository.watchers_count),
                  content_tag(:span, "watcher".pluralize(repository.watchers_count), class: "ml-1"),
                ])
              end,
            ])
          end
        end

        def warning_message
          case stage
          when 2
            second_warning_message
          when 3
            has_stars_or_watchers? ? third_warning_message : nil
          else
            nil
          end
        end

        def main_warning_message
          render(Primer::Beta::TimelineItem.new(
            classes: "repository-visibility-change-warning",
          )) do |component|
            component.with_badge(bg: :transparent, color: :subtle, icon: :"dot-fill")
            component.with_body(font_weight: :bold) { WARNING_MESSAGES[new_visibility][0] }
          end
        end

        def second_warning_message
          other_messages = WARNING_MESSAGES[new_visibility][1..].map do |message|
            render(Primer::Beta::TimelineItem.new(
              p: 0,
              condensed: true,
              classes: "repository-visibility-change-warning",
            )) do |component|
              component.with_badge(bg: :transparent, color: :subtle, icon: :"dot-fill")
              component.with_body { message % { github_url: GitHub.url } }
            end
          end

          safe_join([
            content_tag(:hr),
            content_tag(:div, class: "mt-2") do
              safe_join([
                show_main_warning_and_counts? ? main_warning_message : nil,
                show_main_warning_and_counts? ? stars_and_watchers : nil,
              ] + other_messages)
            end,
          ])
        end

        def third_warning_message
          safe_join([
            if show_main_warning_and_counts?
              content_tag(:div, class: "flash mt-3 flash-warn") do
                safe_join([primer_octicon(:alert), WARNING_ALERT])
              end
            else
              nil
            end,
            show_main_warning_and_counts? ? main_warning_message : nil,
            show_main_warning_and_counts? ? stars_and_watchers : nil,
          ])
        end

        memoize def has_stars_or_watchers?
          repository.stargazer_count.positive? || repository.watchers_count.positive?
        end

        memoize def show_main_warning_and_counts?
          new_visibility != "public" && has_stars_or_watchers?
        end
      end
    end
  end
end
