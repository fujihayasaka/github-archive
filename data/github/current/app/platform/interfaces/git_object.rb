# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module GitObject
      include Platform::Interfaces::Base
      description "Represents a Git object."

      field :repository, Objects::Repository, "The Repository the Git object belongs to", null: false

      field :id, ID, description: "The Node ID of the GitObject object",  method: :global_relay_id, null: false

      field :oid, Scalars::GitObjectID, "The Git object ID", null: false
      field :abbreviated_oid, String, "An abbreviated version of the Git object ID", null: false

      url_fields prefix: "commit", description: "The HTTP URL for this Git object" do |obj|
        template = Addressable::Template.new("/{owner}/{name}/commit/{oid}")
        template.expand owner: obj.repository.owner.display_login, name: obj.repository.name, oid: obj.oid
      end

      def self.load_from_next_global_id(parsed_id)
        load_from_repo_by_oid(parsed_id.parts[:repo_id], parsed_id.parts[:oid])
      end

      def self.load_from_global_id(id)
        repo_id, oid = id.split(":", 2)
        load_from_repo_by_oid(repo_id, oid)
      end

      def self.load_from_repo_by_oid(repo_id, oid)
        Loaders::ActiveRecord.load(::Repository, repo_id.to_i, security_violation_behaviour: :nil).then do |repo|
          if repo
            Loaders::GitObject.load(repo, oid)
          end
        end
      end
    end
  end
end
