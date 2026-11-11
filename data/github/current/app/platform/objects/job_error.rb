# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class JobError < Platform::Objects::Base
      description "A error of a background job."

      def self.async_api_can_access?(permission, object)
        # Doesn't require special checks here because JobError is not a database model
        # and we're delegating the permission check `JobStatus` which is
        # the only object referencing this object
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      def self.async_viewer_can_see?(permission, object)
        # This object is the graphQL representation of a JobStatusSubscription errors
        # see packages/substrate/app/models/job_status_subscription.rb:27
        # since this is just a hash, we can't use the normal permission system and
        # rely on the job_status object to do the permission check, which is the parent
        # of this object and only link
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      visibility :internal

      field :node_id, ID, description: "The ID of the failing object.", null: false
      field :message, String, description: "The error message why this fails.", null: true
    end
  end
end
