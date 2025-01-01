# typed: true
# frozen_string_literal: true

require "dependency-snapshots-api-proto"

module DependencySnapshot
  module EntitySerializer
    class Push
      extend T::Sig

      ##
      # The 'push' parameter is actually an instance of the Push model (ie. ::Push)
      # but that class is scoped to the "Repository" package. IPush is the public-facing interface.
      #
      sig { params(push: Repositories::IPush).returns(Github::DependencySnapshotsApi::Entities::Push) }
      def self.serialize(push)

        Github::DependencySnapshotsApi::Entities::Push.new(
          before: push.before,
          after: push.after,
          committed_at: push.commits.last&.committed_date,
          ref: push.ref,
          created_at: push.created_at.to_time,
          # TODO: updated_at doesn't exist on IPush although it technically exists on 'Push'
          # updated_at: push.updated_at,
          pushed_at: push.pushed_at.to_time
          # TODO: populate push_type
        )
      end
    end
  end
end
