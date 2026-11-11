# typed: true
# frozen_string_literal: true

require "monolith-twirp-registrymetadata-core"

module Api::Internal::Twirp::Registrymetadata
  module Core
    module V1
      # This is hacky, because Permissions::Granters::RoleGranter needs the object of this class.
      # When granting permissions, we typically have access to the protobuf response,
      # which is then passed to our wrapper object (PackageRegistry::Package).
      #
      # Since we just have the ID in the repo sync request and no ID at all for logins, we're passing this struct to avoid fetching the package.
      # Even if we did want to re-fetch the package, there's no API to fetch by ID (only by namespace (owner) + ecosystem + name).
      # Some programmatic actor checks depend on being able to resolve the owner and repository hence the setters for those IDs.
      class PackageWrapper
        attr_reader :id, :owner_id, :repo_id

        def initialize(id)
          @id = id
        end

        def user_role_target_type
          "Package"
        end

        def owner_id=(owner_id)
          @owner_id = owner_id
        end

        def repo_id=(repo_id)
          @repo_id = repo_id
        end
      end
    end
  end
end
