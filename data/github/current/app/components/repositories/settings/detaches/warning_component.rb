# typed: true
# frozen_string_literal: true

# rubocop:disable ViewComponent/ComponentsHaveUnitTests
# tests are here: test/components/repositories/settings/detaches/warning_component_test.rb
module Repositories
  module Settings
    module Detaches
      class WarningComponent < ApplicationComponent
        WARNING_ALERT = "Unexpected bad things will happen if you don’t read this!"

        def initialize(repository:, stage:)
          @repository = repository
          @stage = stage
        end

        private

        attr_reader :repository, :stage

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
                remove_relationship_message,
                become_standalone_message,
                cannot_rejoin_network_message,
              ].compact)
            end,
          ])
        end

        def remove_relationship_message
          build_display_message(
            safe_join([
              "This will permanently remove the fork relationship to the upstream repository ",
              content_tag(:strong, repository.parent&.name_with_display_owner),
              ".",
            ].compact),
          )
        end

        def become_standalone_message
          build_display_message(
            safe_join([
              content_tag(:strong, repository.name_with_display_owner),
              " will become a standalone repository and will no longer be able to fetch upstream updates",
              " or propose changes to the upstream repository ",
              content_tag(:strong, repository.parent&.name_with_display_owner),
              ".",
            ].compact),
          )
        end

        def cannot_rejoin_network_message
          build_display_message(
            safe_join([
              content_tag(:strong, repository.name_with_display_owner),
              " cannot rejoin the fork network.",
            ].compact),
          )
        end

        def build_display_message(message)
          render(Primer::Beta::TimelineItem.new(
            p: 0,
            condensed: true,
            classes: "repository-detach-warning",
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
