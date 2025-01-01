# typed: false
# frozen_string_literal: true

module Profiles
  module User
    module Achievements
      module UnlockingEvents
        class AchievementRepositoryListComponent < ::Profiles::User::Achievements::UnlockingEvents::BaseComponent
          INACCESSIBLE_MESSAGE = "inaccessible"
          REPOSITORY_LIMIT = 3.freeze

          def call
            repositories_to_show = achievement_repository_list.repositories.
              lazy.
              select { |repository| visible_models.include?(repository) }.
              first(REPOSITORY_LIMIT)

            return achievement_explanation(INACCESSIBLE_MESSAGE) unless repositories_to_show.any?

            repositories_to_render = repositories_to_show.map do |repository|
              render Primer::Beta::TimelineItem.new(
                condensed: true,
                classes: "achievement-history-tier",
              ) do |component|
                component.with_badge(
                  icon: "dot-fill",
                  color: :subtle,
                  mt: 0,
                  mr: 0,
                  bg: :transparent
                )
                component.with_body(font_size: :normal, color: :default, mt: 0) do
                  content_tag(:a, repository.name_with_display_owner, class: "Link", href: repository_path(repository))
                end
              end
            end

            safe_join(repositories_to_render + [achievement_explanation])
          end

          def repository_limit
            REPOSITORY_LIMIT
          end

          private

          alias_method :achievement_repository_list, :unlocking_model

          def achievement_explanation(explanation = render_explanation)
            render Primer::Beta::TimelineItem.new(
              condensed: true,
              classes: "achievement-history-tier",
            ) do |component|
              component.with_badge(icon: "dot-fill", color: :subtle, mt: 0, mr: 0, bg: :transparent)
              component.with_body(font_size: :normal, color: :muted, mt: 0) do
                content_tag(:span, explanation)
              end
            end
          end
        end
      end
    end
  end
end
