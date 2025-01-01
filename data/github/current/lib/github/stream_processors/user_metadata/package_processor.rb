# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module UserMetadata
      class PackageProcessor < UserMetadataBaseProcessor
        include Registry::QueryHelper

        DEFAULT_GROUP_ID = "package_processor"
        DEFAULT_SUBSCRIBE_TO = [
          /package_registry.v0.PackagePublished\Z/,
          /package_registry.v0.PackageDeleted\Z/,
          /github.user_metadata.v1.Recalculation\Z/,
          /registry_metadata.v0.PackagePublished\Z/,
          /registry_metadata.v0.PackageDeleted\Z/,
        ]
        HYDRO_TARGET_PROCESSOR_NAME = :PACKAGES.freeze

        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          self.metric_prefix = "user_metadata_processor.package"
          self.dead_letter_topic = "user_metadata.v0.Package.DeadLetter"
        end

        # Public: User metadata that this stream processor should update for a given user.
        #
        # event - the UserMetadataEvent currently being processed
        # user  - a User with metadata affected by the event being processed
        #
        # Returns a Hash of metadata key/value pairs to update for the specified user.
        def metadata_updates(event, user)
          with_read do
            {
              packages_count: actor_public_packages_count(user),
              packages_public_and_private_count: actor_public_and_private_packages_count(user),
            }
          end
        end

        private

        def actor_public_packages_count(user)
          _, _, total_unfiltered_count = packages_for_query(
            current_user: user,
            user_session: nil,
            owner: user,
            per_page: 1,
            use_cached_versions: true,
            visibility: "public",
          )
          total_unfiltered_count
        end

        def actor_public_and_private_packages_count(user)
          _, _, total_unfiltered_count = packages_for_query(
            current_user: user,
            user_session: nil,
            owner: user,
            per_page: 1,
            use_cached_versions: true,
          )
          total_unfiltered_count
        end
      end
    end
  end
end
