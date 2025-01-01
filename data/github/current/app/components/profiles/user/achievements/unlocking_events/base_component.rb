# typed: true
# frozen_string_literal: true

module Profiles
  module User
    module Achievements
      module UnlockingEvents
        # rubocop:disable ViewComponent/ComponentsHaveUnitTests
        class BaseComponent < Profiles::User::Achievements::BaseComponent
          include CommentsHelper

          def initialize(achievement:, visible_models:, unlocking_model: false, is_hovercard: false, profile_user: nil)
            @achievement = achievement
            @visible_models = visible_models
            @unlocking_model = unlocking_model
            @is_hovercard = is_hovercard
            @profile_user = profile_user || achievement.user
          end

          def call
            render Primer::Beta::TimelineItem.new(
              condensed: true,
              classes: "achievement-history-tier",
              test_selector: "unlocking-event-#{achievement.tier}",
            ) do |component|
              component.with_badge(
                icon: "dot-fill",
                color: :subtle,
                mt: 0,
                mr: 0,
                bg: :transparent
              )
              component.with_body(font_size: :small, color: :muted, mt: 0) do
                safe_join([
                  render_model,
                  " · ",
                  content_tag(:span, render_explanation),
                ])
              end
            end
          end

          private

          attr_reader :achievement, :profile_user, :visible_models

          def hovercard?
            @is_hovercard
          end

          def unlocking_model
            if @unlocking_model == false
              unlocking_model_type = achievement.unlocking_model_type

              if unlocking_model_type == "Repository" && achievement.achievable.needs_unlocking_oid?
                achievement.unlocking_commit
              else
                achievement.unlocking_model
              end
            else
              @unlocking_model
            end
          end

          # Internal: Override :authorizing_model when the validated unlocking model differs from the rendered one,
          # such as with a Commit.
          alias_method :authorizing_model, :unlocking_model

          # Internal: Return true if the unlocking model for this achievement tier should be visible to the current
          # viewer, accounting for both logical authorization and CAP filter outcome.
          def is_accessible?
            visible_models.include?(authorizing_model)
          end

          def inaccessible_message
            "inaccessible"
          end

          def render_model
            if is_accessible?
              render_accessible_model
            else
              render_inaccessible_model
            end
          end

          def render_accessible_model
            raise "#{self.class.name} must override #render_accessible_model"
          end

          def render_inaccessible_model
            content_tag(:span, inaccessible_message, class: "color-fg-muted")
          end

          def render_explanation
            render_text_with_substitutions(achievement.unlocking_explanation_template)
          end
        end
        # rubocop:enable ViewComponent/ComponentsHaveUnitTests
      end
    end
  end
end
