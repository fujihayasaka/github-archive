# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module UserMetadata
      class SponsorProcessor < UserMetadataBaseProcessor
        HYDRO_TARGET_PROCESSOR_NAME = :SPONSORS.freeze
        DEFAULT_GROUP_ID = "sponsor_processor"
        DEFAULT_SUBSCRIBE_TO = [
          /github.sponsors.v1.SponsorshipCreateCancel\Z/,
          /github.user_metadata.v1.Recalculation\Z/,
          /github.sponsors.v1.SponsorshipPreferenceChange\Z/,
          /github.sponsors.v1.SponsorshipExpire\Z/,
        ]

        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          self.metric_prefix = "user_metadata_processor.sponsor"
          self.dead_letter_topic = "user_metadata.v0.Sponsor.DeadLetter"
        end

        private

        # Public: User metadata that this stream processor should update for a given user.
        #
        # event - the UserMetadataEvent currently being processed
        # user  - a User with metadata affected by the event being processed
        #
        # Returns a Hash of metadata key/value pairs to update for the specified user.
        def metadata_updates(event, user)
          with_read do
            if event.recalculation?
              sponsor_metadata(user).merge(sponsorable_metadata(user))
            elsif event.user_is_sponsor?(user)
              sponsor_metadata(user)
            elsif event.user_is_sponsorable?(user)
              sponsorable_metadata(user)
            end
          end
        end

        def sponsor_metadata(user)
          {
            has_sponsoring_badge: user.public_github_sponsor?,
            sponsoring_count: user.public_sponsoring_count,
            inactive_sponsoring_count: user.inactive_public_sponsoring_count,
            sponsoring_public_and_private_count: user.public_and_private_sponsoring_count,
            inactive_sponsoring_public_and_private_count: user.inactive_public_and_private_sponsoring_count,
          }
        end

        def sponsorable_metadata(user)
          {
            sponsors_count: user.public_sponsors_count,
            inactive_sponsors_count: user.inactive_public_sponsors_count,
            sponsors_public_and_private_count: user.public_and_private_sponsors_count,
            inactive_sponsors_public_and_private_count: user.inactive_public_and_private_sponsors_count,
          }
        end
      end
    end
  end
end
