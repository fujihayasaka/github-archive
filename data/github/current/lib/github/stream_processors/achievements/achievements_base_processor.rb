# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Achievements
      class AchievementsBaseProcessor < BaseProcessor
        include TransientErrorResiliency

        RECALCULATION_TOPIC_PATTERN = /github\.achievements\.v1\.Recalculation\Z/
        RECALCULATION_SKIP_MESSAGE = "recalculation triggered for another achievements processor"
        MAX_WAIT_SECONDS = 8.freeze

        options[:min_bytes] = 1.kilobyte
        options[:max_wait_time] = 1.second
        options[:session_timeout] = 60.seconds
        options[:socket_timeout] = 65.seconds
        options[:start_from_beginning] = false
        options[:max_bytes_per_partition] = 100.kilobytes

        def name
          self.class::HYDRO_TARGET_PROCESSOR_NAME
        end

        def process_message(message)
          event = Events::AchievementEvent.from(message, self)

          GitHub.logger.with_named_tags(
            "gh.processor.name" => name,
            "messaging.kafka.source.name" => message.topic,
            "messaging.kafka.source.partition" => message.partition,
            "messaging.kafka.message.offset" => message.offset,
            "messaging.message.id" => message.id,
            "gh.achievement.event.name" => event.name,
          ) do
            time_waited_in_seconds = 0

            if event.wait_for_replication?
              time_waited_in_seconds = wait_for_replication!(timestamp: message.timestamp, cluster_names: event.cluster_names)
            end

            if event.skip?
              GitHub.logger.info(
                "gh.achievement.event.skip" => true,
                "gh.achievement.event.skip_reason" => event.skip_reason,
              )
              return message.skip(event.skip_reason)
            end

            GitHub.dogstats.distribution_time("achievements_processor.advance_achievement_for.duration") do
              GitHub.logger.info({
                "gh.achievement.event.skip" => false,
                "gh.achievement.event.achieving_user_ids" => event.achieving_users.pluck(:id),
                "gh.achievement.event.unlocking_model.type" => event.unlocking_model.class.name,
                "gh.achievement.event.unlocking_model.id" => event.unlocking_model&.id,
                "gh.achievement.event.waited_for_clusters" => event.wait_for_replication? ? event.cluster_names : nil,
                "gh.achievement.event.time_waited_in_seconds" => event.wait_for_replication? ? time_waited_in_seconds : nil,
              }.compact)

              Failbot.push(
                stream_processor: self.class.name.underscore,
                group_id: group_id,
                message_schema: message.schema,
              ) do
                with_write { advance_achievement_for(event) }
              end
            end
          end
        end

        private

        def advance_achievement_for(event)
          event.achieving_users.each do |user|
            achievement_progression = event.achievement_progression(subject_user: user)
            achievement_progression.save unless achievement_progression.persisted?

            achievement_progression.increment_count!(:PUBLIC) if event.public?
            achievement_progression.increment_count!(:PRIVATE)

            achievement_attributes = {
              user: user,
              achievable_slug: event.achievable_slug,
              unlocking_model: event.unlocking_model,
            }
            next_public_tier_threshold = event.next_achievement_tier_threshold(
              subject_user: user,
              subject_visibility: :PUBLIC,
            )
            next_private_tier_threshold = event.next_achievement_tier_threshold(
              subject_user: user,
              subject_visibility: :PRIVATE,
            )

            GitHub.dogstats.distribution_time("achievements_processor.create_achievement_with_eligibility_check.duration") do
              if !event.already_has_highest_tier_achievement?(
                subject_user: user,
                subject_visibility: :PRIVATE,
              ) && event.private_achievement_eligible?(user, achievement_progression.private_count)
                next_private_tier = event.next_achievement_tier(
                  subject_user: user,
                  subject_visibility: :PRIVATE,
                )

                GitHub.dogstats.distribution_time(
                  "achievements_processor.create_private_achievement.duration",
                ) do
                  GitHub.logger.info({
                    "gh.achievement.event.achieving_user_id" => user.id,
                    "gh.achievement.event.created" => true,
                    "gh.achievement.event.threshold_achieved" => achievement_progression.private_count,
                    "gh.achievement.event.threshold_needed" => next_private_tier_threshold,
                    "gh.achievement.event.tier" => next_private_tier,
                    "gh.achievement.event.visibility" => :PRIVATE,
                  })

                  create_achievement(
                    achievement_attributes.merge(
                      visibility: :private_scope,
                      tier: next_private_tier,
                    ),
                  )
                end
              end

              if !event.already_has_highest_tier_achievement?(
                subject_user: user,
                subject_visibility: :PUBLIC,
              ) && event.public_achievement_eligible?(user, achievement_progression.public_count)
                next_public_tier = event.next_achievement_tier(
                  subject_user: user,
                  subject_visibility: :PUBLIC,
                )

                GitHub.dogstats.distribution_time(
                  "achievements_processor.create_public_achievement.duration",
                ) do
                  GitHub.logger.info({
                    "gh.achievement.event.achieving_user_id" => user.id,
                    "gh.achievement.event.created" => true,
                    "gh.achievement.event.threshold_achieved" => achievement_progression.public_count,
                    "gh.achievement.event.threshold_needed" => next_public_tier_threshold,
                    "gh.achievement.event.tier" => next_public_tier,
                    "gh.achievement.event.visibility" => :PUBLIC,
                  })

                  create_achievement(
                    achievement_attributes.merge(
                      visibility: :public_scope,
                      tier: next_public_tier,
                    ),
                  )
                end
              end
            end
          end
        end

        def create_achievement(attrs)
          Achievement.create!(attrs)
        rescue ActiveRecord::RecordInvalid => e
          if e.record.errors.of_kind?(:achievable_slug, :taken) || e.record.errors.of_kind?(:tier)
            # This is a race condition. Another Hydro processor has granted this user an achievement tier in the span
            # of time between when we have read the existing highest tier and when we have attempted to grant this
            # one.
            #
            # Do nothing, the other processor "won".
          else
            raise e
          end
        rescue ActiveRecord::RecordNotUnique
          # Same as the RecordInvalid above, but the validation process didn't catch the problem and the database did.
          # We still want to ignore.
        end

        def inspect
          "<processor>"
        end

        def wait_for_replication!(timestamp:, cluster_names:)
          last_writes = cluster_names.each_with_object({}) do |name, last_written_at_by_cluster|
            last_written_at_by_cluster[name.to_sym] = { time: format_time_for_replication(timestamp) }
          end

          replication_waiter = WaitForReplication.new(
            last_writes,
            max_wait_seconds: MAX_WAIT_SECONDS,
          )

          replication_waiter.wait!
          replication_waiter.waited
        end

        def format_time_for_replication(timestamp)
          Timestamp.from_time(Time.at(timestamp))
        end
      end
    end
  end
end
