# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class GistStargazerCount < Platform::Loader
      def self.load(gist, viewer: nil, filter_spam: false)
        self.for(viewer, filter_spam, **{}).load(gist.id)
      end

      def initialize(viewer = nil, filter_spam = false)
        @viewer = viewer
        @filter_spam = filter_spam
      end

      def fetch(gist_ids)
        relation = ::GistStar.where(gist_id: gist_ids)

        if filter_spam
          user_ids = relation.distinct.pluck(:user_id)
          non_spammy_user_ids = User.where(id: user_ids).filter_spam_for(viewer).pluck(:id)
          relation = relation.where(user_id: non_spammy_user_ids)
        end

        Hash.new(0).merge(relation.group(:gist_id).count)
      end

      private

      attr_reader :viewer, :filter_spam
    end
  end
end
