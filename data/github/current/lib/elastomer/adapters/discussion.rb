# typed: true
# frozen_string_literal: true

module Elastomer::Adapters
  class Discussion < ::Elastomer::Adapter
    DEFAULT_MAX_BYTESIZE = 10.megabytes

    # Public: Returns the name of the Index class responsible for storing the
    # generated documents.
    sig { returns String }
    def self.index_name
      "Discussions"
    end

    def self.mysql_cluster
      ::Discussion.cluster_name
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
    sig { returns T.nilable(::Discussion) }
    def model
      @model ||= ::Discussion.find_by(id: document_id)
    end

    # Document routing information used to co-locate all team discussions for a given
    # organization on a single shard in the search index.
    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def document_routing
      @document_routing ||= model&.repository_id
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    # Public: Construct a document suitable for indexing in ElasticSearch and
    # return it as a Hash.
    #
    # Returns the ElasticSearch document as a Hash.
    sig { returns T::Hash[Symbol, T.untyped] }
    def to_hash
      model = self.model
      if model.nil?
        raise Elastomer::ModelMissing,
          "The data model has not been set, or the document ID does not exist in the database."
      end

      return @hash if defined? @hash

      sanitized_body = ::Search.clean_and_sanitize(model.body)

      # truncate dups input so don't do that unless it's necessary
      if sanitized_body.bytesize > max_bytesize
        sanitized_body = sanitized_body.truncate(max_bytesize, separator: " ", omission: "")
      end

      increment_bytesize(sanitized_body)

      num_reactions = ActiveRecord::Base.connected_to(role: :reading) { model.reactions_count }.values.sum
      num_comments = model.comment_count
      label_names = model.labels.map(&:lowercase_name)

      @hash = {
        _id: document_id.to_s,
        _type: document_type,
        _routing: document_routing,
        title: model.title,
        body: sanitized_body,
        state: model.state,
        state_reason: model.state_reason,
        closed_at: model.closed_at,
        user_id: model.user_id,
        answered_by_id: model.answered_by_id,
        repository_id: model.repository_id,
        public: model.public?,
        num_comments: num_comments,
        # Weight comments more heavily than reactions
        interaction_score: (num_comments * 3) + num_reactions,
        num_interactions: num_comments + num_reactions,
        total_upvotes: model.total_upvotes,
        answered: model.answered?,
        unanswered: model.unanswered?,
        verified: model.verified?,
        locked: model.locked?,
        participating_user_ids: model.participants.map(&:id),
        number: model.number,
        created_at: model.created_at,
        updated_at: model.updated_at,
        comments: comments_for(model),
        category_id: model.discussion_category_id,
        labels: label_names,
        bumped_at: model.bumped_at,
        num_reactions: num_reactions,
        reactions: ActiveRecord::Base.connected_to(role: :reading) { model.reactions_count },
      }
    end

    # Internal: Given a Discussion, return an Array of comments converted into
    # document Hashes suitable for indexing into ElasticSearch.
    #
    # Returns the Array of comments converted to document Hashes.
    sig { params(discussion: ::Discussion).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def comments_for(discussion)
      comments = discussion.comments
      comments = comments.each_with_object([]) do |comment, memo|
        hash = comment_hash(comment)
        increment_bytesize(hash.fetch(:body))

        # Once max_bytesize is exceeded, stop converting comments
        if bytesize_estimate > max_bytesize
          break memo
        else
          memo << hash
        end
      end
      comments.compact
    end

    # Internal: Given a DiscussionComment, return a document Hash for indexing in Elasticsearch.
    #
    # Returns a Hash.
    sig { params(comment: ::DiscussionComment).returns(T::Hash[Symbol, T.untyped]) }
    def comment_hash(comment)
      {
        comment_id: comment.id,
        body: ::Search.clean_and_sanitize(comment.body),
        user_id: comment.user_id,
        created_at: comment.created_at,
        updated_at: comment.updated_at,
      }
    end

    # Internal: Given a string, increment the bytesize estimate.
    #
    # Returns the bytesize.
    sig { params(str: String).returns(Integer) }
    def increment_bytesize(str)
      self.bytesize_estimate += str.bytesize
    end
  end
end
