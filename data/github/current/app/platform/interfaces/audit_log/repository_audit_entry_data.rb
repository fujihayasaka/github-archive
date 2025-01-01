# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module AuditLog
      module RepositoryAuditEntryData
        include Platform::Interfaces::Base

        description "Metadata for an audit entry with action repo.*"


        field :repository_name, String, null: true, description: "The name of the repository"
        def repository_name
          @object.get :repo
        end

        field :repository, Platform::Objects::Repository, null: true, description: "The repository associated with the action"
        def repository
          Loaders::ActiveRecord.load(::Repository, @object.get(:repo_id), security_violation_behaviour: :nil)
        end

        url_fields prefix: :repository, null: true, description: "The HTTP URL for the repository" do |audit_entry|
          Loaders::ActiveRecord.load(::Repository, audit_entry.get(:repo_id), security_violation_behaviour: :nil).then do |repository|
            if repository.present?
              repository.async_owner.then do |owner|
                template = Addressable::Template.new("/{owner}/{repository}")
                template.expand(owner: owner.display_login, repository: repository.to_param)
              end
            end
          end
        end

        # internal only

        field :repository_database_id, Integer, null: true, visibility: :internal, description: "The database ID of the repository"
        def repository_database_id
          @object.get :repo_id
        end
      end
    end
  end
end
