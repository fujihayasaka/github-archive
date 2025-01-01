# typed: false
# frozen_string_literal: true

module Platform
  module Interfaces
    module CommittishObject
      include Platform::Interfaces::Base
      description "Represents a git object that is bound under a commit."

      visibility :internal

      field :repository, Objects::Repository, "The repository associated with this object.", null: false

      field :id, ID, description: "The Node ID of the CommittishObject object", method: :global_relay_id, null: false

      field :revision, Objects::CommitRevision, "The commit revision object associated with this object.", null: false

      field :file_path, String, description: <<~MD, null: false do
          The file's path from the tree root.

          Examples
          * "README.md"
          * "lib"
          * "lib/main.c"
        MD
      end

      field :object, Interfaces::GitObject, "The git object this file path resolves to.", resolver_method: :git_object, null: false

      def git_object
        object.async_object
      end
    end
  end
end
