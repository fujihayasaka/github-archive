# typed: true
# frozen_string_literal: true

module Platform::Objects::Query::Blog
  extend T::Sig
  extend ActiveSupport::Concern
  include ::Platform
  include ::GraphQL::Schema::Member::GraphQLTypeNames

  ESSENTIAL_BROADCAST_KEYS = T.let(%w[
    date_published
    title
    url
    content_html
  ].freeze, T::Array[String])

  included do
    T.bind(self, T.class_of(Platform::Objects::Query))
    field :latest_unread_broadcast, Objects::BlogBroadcast, visibility: :internal, description: "Find the most recent unread broadcast post for the viewer.", null: true

    sig { returns(T.nilable(Platform::Models::BlogBroadcast)) }
    def latest_unread_broadcast
      return nil unless GitHub.blog_enabled?
      return nil unless @context[:viewer]

      broadcasts = Platform::Helpers::BlogBroadcast.json_feed
      return nil if broadcasts.blank?

      last_read_id = @context[:viewer].last_read_broadcast_id
      latest_broadcast = broadcasts.first

      ESSENTIAL_BROADCAST_KEYS.each do |key|
        return nil if latest_broadcast[key].blank?
      end

      id = DateTime.parse(latest_broadcast["date_published"]).to_i
      return nil if last_read_id && last_read_id >= id

      Platform::Models::BlogBroadcast.new(
        id: id,
        title: latest_broadcast["title"],
        url: latest_broadcast["url"],
        content: latest_broadcast["content_html"],
      )
    end

    field :unread_broadcasts_count, Integer, visibility: :internal, description: "Get the number of unread broadcast posts (or -1 if unknown) for the viewer.", null: false

    sig { returns(Integer) }
    def unread_broadcasts_count
      return 0 unless GitHub.blog_enabled?
      return 0 unless @context[:viewer]

      broadcasts = Platform::Helpers::BlogBroadcast.json_feed
      return 0 if broadcasts.blank?

      broadcasts.reject! do |broadcast|
        ESSENTIAL_BROADCAST_KEYS.find { |k| broadcast[k].blank? }
      end
      return 0 if broadcasts.blank?

      last_read_id = @context[:viewer].last_read_broadcast_id
      return -1 unless last_read_id

      broadcasts_ids = broadcasts.map do |broadcast|
        DateTime.parse(broadcast["date_published"]).to_i
      end

      return  0 if last_read_id >= broadcasts_ids.first
      return -1 if last_read_id <  broadcasts_ids.last
      [last_read_id, *broadcasts_ids].sort.reverse.index(last_read_id) || -1
    end

    field :viewer_can_create_posts, Boolean, visibility: :internal, description: "Is the viewer allowed to create new blog posts.", null: false

    sig { returns(T::Boolean) }
    def viewer_can_create_posts
      return false unless GitHub.blog_enabled?
      return false unless @context[:viewer]
      @context[:viewer].blogger?
    end
  end
end
