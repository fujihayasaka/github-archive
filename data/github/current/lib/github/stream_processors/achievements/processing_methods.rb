# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Achievements
      module ProcessingMethods
        extend ActiveSupport::Concern

        class AchievementProcessingError < StandardError; end

        included do
          class_attribute :achieving_user_references

          def self.achieving_users(user_references)
            self.achieving_user_references = Array.wrap(user_references)
          end

          def self.achieving_user(user_reference)
            self.achieving_user_references = [user_reference]
          end

          def self.achievement_visibility(visibility_reference)
            define_method(:visibility) { method(visibility_reference).call }
          end

          def self.public_achievement(eligible_if: nil, eligible_unless: nil, send_args: false)
            verify_arguments(eligible_if, eligible_unless)

            define_method(:public_achievement_eligible?) do |user, count|
              return false if eligible_if == false || eligible_unless == true
              return true if eligible_if == true || eligible_unless == false

              method_to_call = if eligible_if
                method(eligible_if)
              elsif eligible_unless
                method(eligible_unless)
              end

              result = if send_args
                method_to_call.call(user, count)
              else
                method_to_call.call
              end

              if eligible_unless
                !result
              else
                result
              end
            end
          end

          def self.private_achievement(eligible_if: nil, eligible_unless: nil, send_args: false)
            verify_arguments(eligible_if, eligible_unless)

            define_method(:private_achievement_eligible?) do |user, count|
              return false if eligible_if == false || eligible_unless == true
              return true if eligible_if == true || eligible_unless == false

              method_to_call = if eligible_if
                method(eligible_if)
              elsif eligible_unless
                method(eligible_unless)
              end

              result = if send_args
                method_to_call.call(user, count)
              else
                method_to_call.call
              end

              if eligible_unless
                !result
              else
                result
              end
            end
          end

          def self.verify_arguments(eligible_if, eligible_unless)
            if !eligible_if.nil? && !eligible_unless.nil?
              raise(
                AchievementProcessingError,
                "You can't have both an `eligible_if` and `eligible_unless` argument!",
              )
            end

            if eligible_if.nil? && eligible_unless.nil?
              raise(
                AchievementProcessingError,
                "You must have either an `eligible_if` or `eligible_unless` argument!",
              )
            end
          end

          def self.wait_for_replication(cluster_names)
            define_method(:cluster_names) { Array.wrap(cluster_names).uniq }
            define_method(:wait_for_replication?) { cluster_names.present? }
          end
        end

        def achieving_users
          @_achieving_users ||= achieving_user_references.flat_map { |ref| method(ref).call }
        end
      end
    end
  end
end
