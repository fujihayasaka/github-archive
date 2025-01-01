# typed: false
# frozen_string_literal: true

module Elastomer::Adapters
  class TeamDiscussion < ::Elastomer::Adapter
    DEFAULT_MAX_BYTESIZE = 10.megabytes

    # Public: Returns the name of the Index class responsible for storing the
    # generated documents.
    def self.index_name
      "TeamDiscussions"
    end

    def self.mysql_cluster
      ::DiscussionPost.cluster_name
    end

    attr_accessor :bytesize_estimate, :max_bytesize

    def initialize(*args)
      super(*args)
      @bytesize_estimate = 0
      @max_bytesize = options.fetch(:max_bytesize, DEFAULT_MAX_BYTESIZE)
    end

    # Public: Accessor for the data model instance. If the `document_id` does
    # not map to any row in the database, then `nil` is returned.
    #
    # Returns the data model instance.
    def model
      @model ||= ::DiscussionPost.find_by_id(document_id)
    end

    # Document routing information used to co-locate all team discussions for a given
    # organization on a single shard in the search index.
    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def document_routing
      @document_routing ||= model&.organization_id
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    # Public: Construct a document suitable for indexing in ElasticSearch and
    # return it as a Hash.
    #
    # Returns the ElasticSearch document as a Hash.
    def to_hash
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

      @hash = {
        _id: document_id.to_s,
        _type: document_type,
        _routing: document_routing,
        title: model.title,
        body: sanitized_body,
        user_id: model.user_id,
        team_id: model.team_id,
        organization_id: model.organization_id,
        pinned: model.pinned?,
        public: model.public?,
        created_at: model.created_at,
        updated_at: model.updated_at,
        reactions: ActiveRecord::Base.connected_to(role: :reading) { model.reactions_count },
        num_reactions: ActiveRecord::Base.
          connected_to(role: :reading) { model.reactions_count }.values.sum,
        replies: replies_for(model),
        num_replies: model.replies.count,
      }
    end

    # Internal: Given a DiscussionPost, return an Array of replies converted into
    # document Hashes suitable for indexing into ElasticSearch.
    #
    # Returns the Array of replies converted to document Hashes.
    def replies_for(discussion_post)
      replies = discussion_post.replies
      replies = replies.each_with_object([]) do |reply, memo|
        hash = reply_hash(reply)
        increment_bytesize(hash.fetch(:body))

        # Once max_bytesize is exceeded, stop converting replies
        if bytesize_estimate > max_bytesize
          break memo
        else
          memo << hash
        end
      end
      replies.compact
    end

    # Internal: Given a DiscussionPostReply, return a document Hash for indexing in Elasticsearch.
    #
    # Returns a Hash.
    def reply_hash(discussion_post_reply)
      {
        discussion_post_reply_id: discussion_post_reply.id,
        body: ::Search.clean_and_sanitize(discussion_post_reply.body),
        user_id: discussion_post_reply.user_id,
        created_at: discussion_post_reply.created_at,
        updated_at: discussion_post_reply.updated_at,
        reactions: ActiveRecord::Base.connected_to(role: :reading) do
          discussion_post_reply.reactions_count
        end,
      }
    end

    # Internal: Given a string, increment the bytesize estimate.
    #
    # Returns the bytesize.
    def increment_bytesize(str)
      self.bytesize_estimate += str.bytesize
    end
  end
end
