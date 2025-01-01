# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Achievements
      module Events
        class StarstruckEvent < AchievementEvent
          ACHIEVABLE_CLASS = Achievable::Starstruck
          MATCHING_SCHEMA = [/github\.v1\.RepositoryStar\Z/].freeze
          UNDER_THRESHOLD_SKIP_MESSAGE = "User has not reached the threshold to unlock or advance the achievement."
          UNLOCKING_MODEL_NOT_FOUND_SKIP_MESSAGE = "Unlocking model cannot be found."
          USER_NOT_FOUND_SKIP_MESSAGE = "User cannot be found."
          USER_ALREADY_ACHIEVED_HIGHEST_TIER_SKIP_MESSAGE = "User already has the highest tier heart on your sleeve achievement."

          private_achievement eligible_if: true
          public_achievement eligible_if: :repository_public?
          achieving_user :user
          achievement_visibility :repository_visibility

          def skip_reason
            return @_skip_reason if defined?(@_skip_reason)

            @_skip_reason = super || begin
              if !unlocking_model
                UNLOCKING_MODEL_NOT_FOUND_SKIP_MESSAGE
              elsif !user
                USER_NOT_FOUND_SKIP_MESSAGE
              elsif already_has_both_highest_tier_achievements?
                USER_ALREADY_ACHIEVED_HIGHEST_TIER_SKIP_MESSAGE
              elsif under_threshold?
                UNDER_THRESHOLD_SKIP_MESSAGE
              end
            end
          end

          def unlocking_model
            return @_unlocking_model if defined?(@_unlocking_model)
            @_unlocking_model = repository
          end

          def user
            return @_user if defined?(@_user)

            @_user = begin
              if org_owned_repository?
                repository_creator
              else
                with_read { User.find_by(id: user_id) }
              end
            end
          end

          def user_id
            if org_owned_repository?
              repository_creator&.id
            else
              message.value.dig(:repository_owner, :id)
            end
          end

          def user_login
            if org_owned_repository?
              repository_creator&.login
            else
              message.value.dig(:repository_owner, :login)
            end
          end

          def user_type
            if org_owned_repository?
              repository_creator&.type
            else
              message.value.dig(:repository_owner, :type)
            end
          end

          private

          def org_owned_repository?
            message.value.dig(:repository_owner, :type) == :ORGANIZATION
          end

          def repository_creator
            return @_repository_creator if defined?(@_repository_creator)

            @_repository_creator = with_read { repository&.created_by }
          end

          def under_threshold?
            repository_star_count < next_achievement_tier_threshold
          end

          def repository
            return @_repository if defined?(@_repository)

            @_repository = begin
              if repository_id = message.value.dig(:repository, :id)
                with_read { Repository.find_by(id: repository_id) }
              end
            end
          end

          def repository_star_count
            message.value.dig(:repository, :stargazer_count) || 0
          end
        end
      end
    end
  end
end
