# typed: true
# frozen_string_literal: true

require "dependency-snapshots-api-proto"

module DependencySnapshot
  module EntitySerializer
    class Repository
      sig { params(repository: ::Repository).returns(Github::DependencySnapshotsApi::Entities::Repository) }
      def self.serialize(repository)

        visibility = case repository.visibility
        when ::Repository::PUBLIC_VISIBILITY
          :PUBLIC
        when ::Repository::INTERNAL_VISIBILITY
          :INTERNAL
        when ::Repository::PRIVATE_VISIBILITY
          :PRIVATE
        else
          :VISIBILITY_UNKNOWN
        end

        Github::DependencySnapshotsApi::Entities::Repository.new(
          id: repository.id,
          name: repository.name,
          visibility: visibility,
          parent_id: repository.parent_id,
          pushed_at: repository.pushed_at,
          default_branch: repository.default_branch.dup.force_encoding(Encoding::UTF_8).scrub!,
          default_branch_ref: repository.get_default_branch.dup.force_encoding(Encoding::UTF_8).scrub!,
          owner_id: repository.owner_id,
          is_fork: repository.fork?,
          is_archived: repository.archived?
        )
      end
    end
  end
end
