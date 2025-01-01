# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Support
  module HelpHub
    module Config
      def community_forum_repo
        @community_forum_repo ||= Repository.find_by(name: "community", owner_login: "community")
      end
      attr_writer :community_forum_repo

      def community_forum_categories
        @community_forum_categories ||= community_forum_repo.available_discussion_categories.all.to_a
      end
    end

    extend Config
  end
end
