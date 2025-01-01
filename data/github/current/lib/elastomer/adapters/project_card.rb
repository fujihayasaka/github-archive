# typed: false
# frozen_string_literal: true

module Elastomer::Adapters

  # The ProjectCard adapter is used to transform a ProjectCard ActiveRecord
  # object into a Hash document that can be indexed in ElasticSearch.
  #
  class ProjectCard < ::Elastomer::Adapter
    # Public: Returns the name of the Index class responsible for storing the
    # generated documents.
    def self.index_name
      "ProjectCards"
    end

    def self.mysql_cluster
      ::ProjectCard.cluster_name
    end

    # Public: Accessor for the data model instance. If the `document_id` does
    # not map to any row in the database, then `nil` is returned.
    #
    # Returns the data model instance.
    #
    def model
      @model ||= ::ProjectCard.find_by_id(document_id)
    end
    alias :project_card :model

    # Document routing information used to co-locate all project cards for a
    # given project on a single shard in the search index.
    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def document_routing
      @document_routing ||= project_card&.project_id
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    # Public: Construct a document suitable for indexing in ElasticSearch and
    # return it as a Hash.
    #
    # Returns the ElasticSearch document as a Hash.
    #
    def to_hash
      return @hash if defined? @hash

      if model.nil?
        raise Elastomer::ModelMissing, "The data model has not been set, or the document ID does not exist in the database."
      end

      # check that the card's project hasn't been deleted (soft or otherwise)
      return if project.nil? || project.marked_for_deletion?

      # check that the card doesn't have deleted content attached
      return if !project_card.is_note? && content.nil?

      @hash = {
        _id: document_id.to_s,
        _routing: document_routing,
        _type: document_type,
        project_id: project.id,
        created_at: project_card.created_at,
        updated_at: project_card.updated_at,
      }

      note_business_id = if project.owner_type == "Repository"
        project.owner&.internal_visibility_business_id
      else
        nil
      end

      type_dependent_attrs = if project_card.is_note?
        {
          type: "note",
          title: project_card.note,
          repo_id: nil,
          public: project.owner_type == "Repository" && project.owner&.public?,
          business_id: note_business_id,
          state: "open",
          author_id: project_card.creator_id,
          labels: [],
          assignee_ids: [],
          milestone_num: nil,
        }
      else
        {
          type: "issue",
          title: content.title,
          repo_id: content.repository_id,
          public: content.repository&.public?,
          business_id: content.repository&.internal_visibility_business_id,
          state: content.pull_request? ? content.pull_request.state.to_s : content.state,
          author_id: content.user_id,
          labels: content.labels.pluck(:name),
          assignee_ids: content.assignee_ids,
          milestone_num: content.milestone&.number,
        }
      end

      @hash.merge!(type_dependent_attrs)

      @hash
    end

    private

    def project
      project_card.project
    end

    def content
      project_card.content
    end
  end  # Project
end  # Elastomer::Index
