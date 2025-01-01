# typed: false
# frozen_string_literal: true

module User::FeedPostDependency
  extend ActiveSupport::Concern

  included do
    has_many :authored_feed_posts, class_name: "FeedPost", foreign_key: :author_id, inverse_of: :author
    has_many :owned_feed_posts, class_name: "FeedPost", foreign_key: :owner_id, inverse_of: :owner
    has_many :feed_post_comments, inverse_of: :user
  end
end
