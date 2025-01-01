# typed: true
# frozen_string_literal: true

module Profiles
  module User
    module Achievements
      module Stafftools
        class IndexComponent < ApplicationComponent
          def initialize(user:, visible_models:)
            @user = user
            @visible_models = visible_models
          end

          private

          attr_reader :user, :visible_models

          delegate :current_repository, to: :helpers

          def page_title
            "#{user} - Achievements"
          end

          VISIBILITY_TITLES = {
            "public_scope" => "Public Achievements",
            "private_scope" => "Private Achievements",
          }.freeze

          def title_for_visibility(visibility)
            VISIBILITY_TITLES.fetch(visibility)
          end

          def achievements_by_visibility_grouped_by_achievable
            scope = user.achievements.order(achievable_slug: :asc, tier: :asc)

            [
              [
                "public_scope",
                existing_achievements_with_next_tier(
                  scope.public_scope.group_by(&:achievable).to_h,
                )
              ],
              [
                "private_scope",
                existing_achievements_with_next_tier(
                  scope.private_scope.group_by(&:achievable).to_h,
                )
              ],
            ]
          end

          def existing_achievements_with_next_tier(existing)
            known_achievables = Achievable.all_known.reject(&:needs_unlocking_oid?)

            known_achievables.each_with_object(existing) do |achievable, acc|
              acc[achievable] ||= []
              highest_achieved_tier = acc[achievable].maximum(:tier)

              unless highest_achieved_tier == achievable.highest_tier
                acc[achievable] << user.achievements.new(
                  achievable_slug: achievable.slug,
                  tier: (highest_achieved_tier || -1) + 1,
                )
              end
            end
          end
        end
      end
    end
  end
end
