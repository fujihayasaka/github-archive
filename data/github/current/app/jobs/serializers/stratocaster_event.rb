# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Serializers
  class StratocasterEvent < ActiveJob::Serializers::ObjectSerializer
    def serialize(event)
      super(
        event_type: event.event_type,
        id: event.id,
        org: event.org,
        public: event.public,
        repo: event.repo,
        sender: event.sender,
        payload: {
          action: event.action,
          comment: { id: event.comment_id },
          forkee: { id: event.forkee_id },
          issue: { id: event.issue_id },
          member: { id: event.member_id },
          pages: event.pages,
          commits: event.commits,
          pull_request: { id: event.pull_request_id },
          push_id: event.push_id,
          pusher_type: event.pusher_type,
          ref_type: event.ref_type,
          release: { id: event.release_id },
          target: { id: event.target_id },
        }
      )
    end

    def deserialize(hash)
      hash.delete(ActiveJob::Arguments::OBJECT_SERIALIZER_KEY)
      Stratocaster::Event.new(hash)
    end

    private

    def klass
      Stratocaster::Event
    end
  end
end
