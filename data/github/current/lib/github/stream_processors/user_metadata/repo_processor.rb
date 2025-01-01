# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module UserMetadata
      class RepoProcessor < UserMetadataBaseProcessor
        HYDRO_TARGET_PROCESSOR_NAME = :REPOSITORIES.freeze
        DEFAULT_GROUP_ID = "repo_processor"
        DEFAULT_SUBSCRIBE_TO = [
          /github.v1.RepositoryArchivedStatusChanged\Z/,
          /github.v1.RepositoryCreate\Z/,
          /github.v1.RepositoryDeleted\Z/,
          /github.v1.RepositoryVisibilityChanged\Z/,
          /github.v1.RepositoryRestored\Z/,
          /github.v1.RepositoryTransfer\Z/,
          /github.user_metadata.v1.Recalculation\Z/,
        ]

        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          self.metric_prefix = "user_metadata_processor.repo"
          self.dead_letter_topic = "user_metadata.v0.Repo.DeadLetter"
        end

        # Public: User metadata that this stream processor should update for a given user.
        #
        # event - the UserMetadataEvent currently being processed
        # user  - a User with metadata affected by the event being processed
        #
        # Returns a Hash of metadata key/value pairs to update for the specified user.
        def metadata_updates(event, user)
          {
            repository_count: public_repositories_count(user),
            repository_public_and_private_count: private_public_repositories_count(user)
          }
        end

        # This processor updates counts related to the repo's owner.
        def repository_association
          :owners
        end

        private

        def public_repositories_count(user)
          with_read { user.public_repositories.count }
        end

        def private_public_repositories_count(user)
          with_read { user.repositories.count }
        end
      end
    end
  end
end
