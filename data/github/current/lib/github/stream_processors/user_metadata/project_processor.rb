# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module UserMetadata
      class ProjectProcessor < UserMetadataBaseProcessor
        HYDRO_TARGET_PROCESSOR_NAME = :PROJECTS.freeze
        DEFAULT_GROUP_ID = "project_processor".freeze
        DEFAULT_SUBSCRIBE_TO = [
          /github\.v1\.ProjectEvent\Z/,
          /github.user_metadata.v1.Recalculation\Z/,
        ].freeze

        # This processor is exempt from the tenant context requirement.
        # It queries for existing projects directly from the user's associations,
        # and thus we don't have to worry about scope leakage.
        exempt_from_tenant_context_requirement

        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          self.metric_prefix = "user_metadata_processor.project"
          self.dead_letter_topic = "user_metadata.v0.Project.DeadLetter"
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
              projects_count: public_projects_count(user),
              projects_public_and_private_count: public_private_projects_count(user)
            }
          end
        end

        private

        def public_projects_count(user)
          user.projects.public_projects.open_projects.size
        end

        def public_private_projects_count(user)
          user.projects.open_projects.size
        end
      end
    end
  end
end
