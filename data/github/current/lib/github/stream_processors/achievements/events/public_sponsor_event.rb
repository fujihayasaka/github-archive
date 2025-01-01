# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Achievements
      module Events

        class PublicSponsorEvent < AchievementEvent
          include GitHub::Memoizer

          ACHIEVABLE_CLASS = Achievable::PublicSponsor

          CREATE_CANCEL_SCHEMA_RX = /github\.sponsors\.v1\.SponsorshipCreateCancel\Z/
          PREFERENCE_CHANGE_SCHEMA_RX = /github\.sponsors\.v1\.SponsorshipPreferenceChange\Z/
          MATCHING_SCHEMA = [CREATE_CANCEL_SCHEMA_RX, PREFERENCE_CHANGE_SCHEMA_RX].freeze

          SPONSORSHIP_NOT_PUBLIC_MESSAGE = "Sponsorship is not created or updated to public."
          SPONSOR_NOT_USER_MESSAGE = "Sponsor is not a user."
          USER_NOT_FOUND_SKIP_MESSAGE = "User cannot be found."
          USER_ALREADY_ACHIEVED_SKIP_MESSAGE = "User already has the public sponsor achievement."
          UNLOCKING_MODEL_NOT_FOUND_SKIP_MESSAGE = "Unlocking model cannot be found."

          private_achievement eligible_if: true
          public_achievement eligible_if: true
          achieving_user :user
          wait_for_replication [Sponsorship.cluster_name]

          memoize def skip_reason
            super || begin
              if !updated_privacy_to_public? && !created_is_public?
                SPONSORSHIP_NOT_PUBLIC_MESSAGE
              elsif !sponsor_is_user?
                SPONSOR_NOT_USER_MESSAGE
              elsif !user
                USER_NOT_FOUND_SKIP_MESSAGE
              elsif already_has_both_highest_tier_achievements?
                USER_ALREADY_ACHIEVED_SKIP_MESSAGE
              elsif !unlocking_model
                UNLOCKING_MODEL_NOT_FOUND_SKIP_MESSAGE
              end
            end
          end

          memoize def unlocking_model
            with_read { Sponsorship.find_by(id: sponsorship_id) }
          end

          def user_message_path
            if is_creation?
              [:sponsorship, :sponsor]
            elsif is_update?
              [:current_sponsorship, :sponsor]
            else
              []
            end
          end

          private

          memoize def is_update?
            message.schema =~ PREFERENCE_CHANGE_SCHEMA_RX
          end

          memoize def is_creation?
            message.schema =~ CREATE_CANCEL_SCHEMA_RX && message.value[:action] == :CREATE
          end

          def updated_privacy_to_public?
            return false unless is_update?

            previous_privacy_level = message.value.dig(:previous_sponsorship, :privacy_level)
            current_privacy_level = message.value.dig(:current_sponsorship, :privacy_level)

            previous_privacy_level != current_privacy_level && current_privacy_level == :PUBLIC
          end

          def created_is_public?
            return false unless is_creation?

            message.value.dig(:sponsorship, :privacy_level) == :PUBLIC
          end

          def dig_current_sponsorship(*attrs)
            if is_creation?
              message.value.dig(:sponsorship, *attrs)
            elsif is_update?
              message.value.dig(:current_sponsorship, *attrs)
            else
              nil
            end
          end

          def sponsor_is_user?
            dig_current_sponsorship(:sponsor, :type) == :USER
          end

          def sponsorship_id
            dig_current_sponsorship(:id) || -1
          end

          def visibility
            :PUBLIC
          end
        end

      end
    end
  end
end
