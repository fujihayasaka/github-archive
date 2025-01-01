# typed: true
# frozen_string_literal: true

require "scientist"

module Elastomer::Adapters
  # The Issue adapter is used to transform an issue ActiveRecord object into a
  # Hash document that can be indexed in ElasticSearch.
  #
  class Issue < ::Elastomer::Adapter

    include Scientist

    DEFAULT_MAX_BYTESIZE = 10.megabytes

    COMMENT_BATCH_SIZE = 500

    # Public: Returns the name of the Index class responsible for storing the
    # generated documents.
    def self.index_name
      "Issues"
    end

    def self.mysql_cluster
      ::Issue.cluster_name
    end

    attr_accessor :bytesize_estimate, :max_bytesize

    def initialize(*args)
      super(*T.unsafe(args))
      @bytesize_estimate = 0
      @max_bytesize = options.fetch(:max_bytesize, DEFAULT_MAX_BYTESIZE)
    end

    # Public: Accessor for the data model instance. If the `document_id` does
    # not map to any row in the database, then `nil` is returned.
    #
    # Returns the data model instance.
    #
    def model
      @model ||= ::Issue.includes(:repository, :labels).find_by(id: document_id)
    end
    alias :issue :model

    # Document routing information used to co-locate all issues for a given
    # repository on a single shard in the search index.
    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def document_routing
      @document_routing ||= (issue && issue.repository_id)
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

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

      # check the that a repository object exists and that issues are enabled
      return unless issue.repository && issue.repository.has_issues
      return if issue.spammy? || issue.pull_request_id

      sanitized_body = ::Search.clean_and_sanitize(issue.body)

      # truncate dups input so don't do that unless it's necessary
      if sanitized_body.bytesize > max_bytesize
        sanitized_body = sanitized_body.truncate(max_bytesize, separator: " ", omission: "")
      end

      increment_bytesize(sanitized_body)

      @hash = {
        _id: document_id.to_s,
        _type: document_type,
        _routing: document_routing,
        title: issue.title,
        body: sanitized_body,
        issue_id: document_id,
        author_id: issue.user_id,
        repo_id: issue.repository_id,
        network_id: issue.repository.network_id,
        public: issue.repository.public?,
        business_id: issue.repository.internal_visibility_business_id,
        archived: issue.repository.archived?,
        state: issue.state,
        number: issue.number,
        labels: issue.labels.map(&:lowercase_name),
        issue_type_name: issue.issue_type&.name&.downcase,
        language: nil,
        language_id: nil,
        created_at: issue.created_at,
        updated_at: issue.updated_at,
        closed_at: issue.closed_at,
        locked_at: issue.locked_at,
        locked: issue.locked?,
        assignee_id: issue.assignees.map(&:id),
        project_ids: issue.projects.pluck(:id),
        memex_project_ids: issue.memex_projects.active_projects.pluck(:id),
        mentioned_user_ids: issue.referenced_user_ids,
        mentioned_team_ids: issue.referenced_team_ids,
        participating_user_ids: issue.participants.map(&:id),
        has_closing_reference: issue.close_issue_references.exists?,
        reactions: ActiveRecord::Base.connected_to(role: :reading) { issue.reactions_count },
        num_reactions: ActiveRecord::Base.connected_to(role: :reading) { issue.reactions_count }.values.sum,
      }

      @hash.delete :labels if @hash[:labels].blank?
      @hash.delete :issue_type_name if @hash[:issue_type_name].blank?

      @hash.delete :mentioned_user_ids if @hash[:mentioned_user_ids].blank?
      @hash.delete :mentioned_team_ids if @hash[:mentioned_team_ids].blank?
      @hash.delete :participating_user_ids if @hash[:participating_user_ids].blank?
      @hash.delete :project_ids if @hash[:project_ids].blank?
      @hash.delete :memex_project_ids if @hash[:memex_project_ids].blank?

      if language = issue.repository.primary_language
        @hash[:language]    = language.linguist_name
        @hash[:language_id] = language.linguist_id
      end

      if issue.milestone
        @hash[:milestone_num]   = issue.milestone.number
        @hash[:milestone_title] = issue.milestone.title.downcase
      end

      @hash[:comments] = comments_for issue
      @hash[:num_comments] = issue.comments.not_spammy.count
      @hash[:num_interactions] = @hash[:num_comments] + @hash[:num_reactions]

      @hash[:state_reason] = issue.state_reason

      if issue.parent.present?
        nwo = issue.parent.repository.name_with_display_owner
        number = issue.parent.number
        @hash[:parent_issue] = "#{nwo}##{number}".downcase
      end
      if issue.sub_issues&.exists?
        @hash[:sub_issue] = issue.sub_issues.map do |sub_issue|
          nwo = sub_issue.repository.name_with_display_owner
          number = sub_issue.number
          "#{nwo}##{number}".downcase
        end
      end

      @hash
    end

    # Internal: Given an Issue, return an Array of comments converted into
    # document Hashes suitable for indexing into ElasticSearch.
    #
    # Returns the Array of comments converted to document Hashes
    def comments_for(issue)
      comments = []

      scope = issue.comments.includes(:reactions).not_spammy.limit(::Issue::COMMENT_LIMIT)

      scope.find_in_batches(batch_size: COMMENT_BATCH_SIZE) do |batch|
        batch.each do |comment|
          hash = comment_hash(comment)
          increment_bytesize(hash.fetch(:body))

          # Once max_bytesize is exceeded, stop converting comments
          if bytesize_estimate > max_bytesize
            break
          else
            comments << hash
          end
        end
      end

      comments.compact
    end

    # Internal: Given a Comment, return a document Hash for indexing in Elasticsearch.
    #
    # Returns a Hash.
    def comment_hash(comment)
      {
        comment_id: comment.id,
        comment_type: "issue",
        body: ::Search.clean_and_sanitize(comment.body),
        author_id: comment.user_id,
        created_at: comment.created_at,
        updated_at: comment.updated_at,
        reactions: ActiveRecord::Base.connected_to(role: :reading) { comment.reactions_count },
      }
    end

    # Internal: Given a string, increment the bytesize estimate.
    #
    # Returns the bytesize.
    def increment_bytesize(str)
      self.bytesize_estimate += str.bytesize
    end

  end  # Issue
end  # Elastomer::Index
