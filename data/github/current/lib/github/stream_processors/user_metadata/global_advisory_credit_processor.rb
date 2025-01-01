# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module UserMetadata
      class GlobalAdvisoryCreditProcessor < UserMetadataBaseProcessor
        HYDRO_TARGET_PROCESSOR_NAME = :GLOBAL_ADVISORY_CREDITS.freeze
        DEFAULT_GROUP_ID = "global_advisory_credit_processor"
        DEFAULT_SUBSCRIBE_TO = [
          /github.security_advisories.v0.AdvisoryCreditCreate\Z/,
          /github.security_advisories.v0.AdvisoryCreditAccept\Z/,
          /github.security_advisories.v0.AdvisoryCreditDecline\Z/,
          /github.security_advisories.v0.AdvisoryCreditDestroy\Z/,
          /github.user_metadata.v1.Recalculation\Z/,
        ].freeze

        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          self.metric_prefix = "user_metadata_processor.global_advisory_credit"
          self.dead_letter_topic = "user_metadata.v0.GlobalAdvisoryCredit.DeadLetter"
        end

        # Public: User metadata that this stream processor should update for a given user.
        #
        # event - the UserMetadataEvent currently being processed
        # user  - a User with metadata affected by the event being processed
        #
        # Returns a Hash of metadata key/value pairs to update for the specified user.
        def metadata_updates(event, user)
          {
            global_advisory_credit_count: global_advisory_credit_count(user)
          }
        end

        private

        def global_advisory_credit_count(user)
          with_read { user.global_advisory_credit_count }
        end
      end
    end
  end
end
