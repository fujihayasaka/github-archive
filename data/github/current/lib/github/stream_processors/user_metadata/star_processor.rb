# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module UserMetadata
      class StarProcessor < UserMetadataBaseProcessor
        include TransientErrorResiliency

        BOUNDING_STAR_LIMIT_THRESHOLD = 500
        HYDRO_TARGET_PROCESSOR_NAME = :STARS.freeze
        DEFAULT_GROUP_ID = "star_processor"
        DEFAULT_SUBSCRIBE_TO = [
          /github.v1.RepositoryStar\Z/,
          /github.v1.TopicStar\Z/,
          /github.v1.RepositoryDeleted\Z/,
          /github.user_metadata.v1.Recalculation\Z/,
        ]

        # Processing star counts should be exempt from the tenant context requirement.
        # The tenant requirement will be enforced upstream when users try to create a star
        # in the first place.
        exempt_from_tenant_context_requirement

        REPOSITORY_DELETED_SCHEMA = "hydro.schemas.github.v1.RepositoryDeleted"

        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          self.metric_prefix = "user_metadata_processor.star"
          self.dead_letter_topic = "user_metadata.v0.Star.DeadLetter"
        end

        # Public: Process a subscribed event in the StarProcessor. Some RepositoryDelete
        # events may represent a large number of users, so ensure that we're sending
        # heartbeats periodically to prevent processor timeouts.
        def process_message(message)
          event = Events::UserMetadataEvent.from(message, self)

          log_context = {
            "gh.processor.name" => name,
            "messaging.kafka.source.name" => message.topic,
            "messaging.kafka.source.partition" => message.partition,
            "messaging.kafka.message.offset" => message.offset,
            "gh.user_metadata.event.name" => event.name,
            "gh.star_processor.user_count" => event.users.size,
          }

          if event.is_a?(Events::RepositoryEvent)
            if message.schema == REPOSITORY_DELETED_SCHEMA
              log_context.merge!(
                "gh.star_processor.fanout" => false,
                "gh.star_processor.deleted_repo_id" => event.deleted_repo_id,
                "gh.star_processor.deleted_repo_owner_id" => event.deleted_repo_owner_id,
              )
            else
              skip_reason = "Unrelated repository event"
              GitHub.logger.info(
                "gh.user_metadata.event.skip" => true,
                "gh.user_metadata.event.skip_reason" => skip_reason,
              )
              return message.skip(skip_reason)
            end
          end

          GitHub.logger.with_named_tags(log_context.merge!("gh.user_metadata.event.skip" => false)) do
            event.users.each do |user|
              if user.spammy?
                GitHub.dogstats.increment("#{metric_prefix}.spammy_user")
                next if GitHub.flipper[:skip_user_metadata_updates_for_spammers].enabled?
              end

              ::UserMetadata.throttle_with_retry(max_retry_count: 5) do
                ::UserMetadata.retry_on_find_or_create_error do
                  updates = with_read { metadata_updates(event, user) }
                  affected_rows = with_write { update_user_metadata(user, updates) }
                  GitHub.logger.info(
                    "code.namespace" => "StreamProcessors::UserMetadata::UserMetadataBaseProcessor",
                    "code.function" => "update",
                    "gh.user.id" => user.id,
                    "gh.user_metadata.updates" => updates.keys.join(","),
                    "gh.user_metadata.affected_rows" => affected_rows,
                  )
                end

                safe_trigger_heartbeat
              end
            end
          end
        end

        # Public: User metadata that this stream processor should update for a given user.
        #
        # event - the UserMetadataEvent currently being processed
        # user  - a User with metadata affected by the event being processed
        #
        # Returns a Hash of metadata key/value pairs to update for the specified user.
        def metadata_updates(event, user)
          star_counts = star_counts(user)
          public_stars_count = star_counts[:public]
          public_and_private_stars_count = star_counts[:public_and_private]

          {
            stars_count: public_stars_count,
            stars_public_and_private_count: public_and_private_stars_count
          }
        end

        # This processor updates counts related to users to have starred the repo,
        # and the counts should no longer include inactive repos, ie. repos that
        # have been soft-deleted.
        def repository_association
          :starrers
        end

        private

        def star_counts(user)
          with_read do
            star_count = Stars.domain.user_starred_objects_count(user.id)
            if star_count > BOUNDING_STAR_LIMIT_THRESHOLD
              { public: star_count, public_and_private: star_count }
            else
              topic_star_count = user.stars.topics.size

              repo_star_counts_by_visibility = Hash.new(0).merge(
                ::Repository.
                  active.
                  where(id: user.starred_repository_ids).
                  filter_spam_and_disabled_for(nil).
                  group(:public).
                  count
              )
              public_repo_star_count = repo_star_counts_by_visibility[true]
              public_and_private_repo_star_count =
                repo_star_counts_by_visibility[true] +
                repo_star_counts_by_visibility[false]

              {
                public: topic_star_count + public_repo_star_count,
                public_and_private: topic_star_count + public_and_private_repo_star_count
              }
            end
          end
        end

        # Check that read replicas are up to date and wait for them if they're
        # not. If we end up needing to wait for more than `max_wait_seconds`
        # a DataUnavailable error will be raised, and our message will be
        # published to DeadLetter.
        #
        # message - GitHub::StreamProcessors::UserMetadata message object
        #
        # Raises `DataUnavailable` | Returns Integer representing number of seconds waited
        def wait_for_replication!(message)
          WaitForReplication.new(
            format_time_for_replication(message.timestamp),
            store_name: Star.cluster_name,
            max_wait_seconds: 8
          ).wait!
        end
      end
    end
  end
end
