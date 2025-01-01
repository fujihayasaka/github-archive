# typed: false
# frozen_string_literal: true

module Elastomer::Adapters

  # The Project adapter is used to transform a project ActiveRecord object
  # into a Hash document that can be indexed in ElasticSearch.
  #
  class Project < ::Elastomer::Adapter
    # Public: Returns the name of the Index class responsible for storing the
    # generated documents.
    def self.index_name
      "Projects"
    end

    def self.mysql_cluster
      ::Project.cluster_name
    end

    # Public: Accessor for the data model instance. If the `document_id` does
    # not map to any row in the database, then `nil` is returned.
    #
    # Returns the data model instance.
    #
    def model
      @model ||= ::Project.includes(:owner).find_by_id(document_id)
    end
    alias :project :model

    # Document routing information used to co-locate all projects for a given
    # owner on a single shard in the search index.
    def document_routing
      project && project.owner_id
    end

    # Public: Construct a document suitable for indexing in ElasticSearch and
    # return it as a Hash.
    #
    # Returns the ElasticSearch document as a Hash.
    #
    def to_hash
      if model.nil?
        raise Elastomer::ModelMissing, "The data model has not been set, or the document ID does not exist in the database."
      end

      return @hash if defined? @hash
      @hash = nil

      # check that the owner exists and project hasn't been soft deleted
      return unless project.owner && !project.deleted_at

      case project.owner_type
      when "Organization"
        org_id = project.owner_id
        repo_id = nil
        user_id = nil
        is_public = project.public?
        business_id = nil
        project_type = "org"
      when "User"
        org_id = nil
        repo_id = nil
        user_id = project.owner_id
        is_public = project.public?
        business_id = nil
        project_type = "user"
      when "Repository"
        org_id = project.owner.organization_id
        repo_id = project.owner_id
        user_id = nil
        is_public = project.owner.public?
        business_id = project.owner.internal_visibility_business_id
        project_type = "repo"
      end

      @hash = {
        _id: document_id.to_s,
        _routing: document_routing,
        _type: document_type,
        name: project.name,
        body: project.body,
        creator_id: project.creator_id,
        updated_at: project.updated_at,
        created_at: project.created_at,
        closed_at: project.closed_at,
        state: project.state,
        org_id: org_id,
        repo_id: repo_id,
        user_id: user_id,
        project_type: project_type,
        public: is_public,
        business_id: business_id,
        number: project.number,
        linked_repository_ids: project.linked_repository_ids,
      }
      @hash
    end
  end  # Project
end  # Elastomer::Index
