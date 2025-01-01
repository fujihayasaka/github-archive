# typed: true
# frozen_string_literal: true

require "monolith-twirp-support-helphub"

module Api::Internal::Twirp::Support
  module HelpHub
    module V1
      # Provides access to Support-relevant data.
      class DiscussionsAPIHandler < Api::Internal::Twirp::Handler
        handles_service(MonolithTwirp::Support::HelpHub::V1::DiscussionsAPIService)

        allow_access_for :user, :client, allowed_clients: %w(helphub).freeze

        SEARCH_QUERY_LENGTH_LIMIT = 250

        # Public: Implementation of the SearchCommunityForum Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Support::HelpHub::V1::SearchCommunityForumRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data, a list of community forum search hits as a repeated
        # MonolithTwirp::Support::HelpHub::V1::SearchCommunityForumResponse.
        def search_community_forum(req, env)
          parsed_query = Search::Queries::DiscussionQuery.normalize(
            Search::Queries::DiscussionQuery.parse(req.query.truncate(SEARCH_QUERY_LENGTH_LIMIT, omission: "", separator: " "))
          )

          hits = Discussion::SearchResult.search(
            query: parsed_query,
            page: 1,
            per_page: 10,
            repo: ::Api::Internal::Twirp::Support::HelpHub.community_forum_repo,
            category_ids: ::Api::Internal::Twirp::Support::HelpHub.community_forum_categories.pluck(:id),
            current_user: nil
          )

          {
            hits: build_discussions_list(hits)
          }
        end

        # Public: Implementation of the FindCommunityDiscussionsByIds Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Support::HelpHub::V1::FindCommunityDiscussionsByIdsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data, a list of community forum search hits as a repeated
        # MonolithTwirp::Support::HelpHub::V1::FindCommunityDiscussionsByIdsResponse.
        def find_community_discussions_by_ids(req, env)
          hits = Discussion.where(repository_id: ::Api::Internal::Twirp::Support::HelpHub.community_forum_repo.id, number: req.ids.to_a).to_a
          {
            hits: build_discussions_list(hits)
          }
        end

        private

        # Private: Convert an array of Discussion objects to the shape Twirp responses expect.
        #
        # hits - The array of Discussion objects.
        #
        # Returns an array of Hash objects with discussion data that matches the
        # SearchCommunityForumHitsItem Twirp definition.
        def build_discussions_list(hits)
          hits.map do |discussion|
            {
              title: discussion.title,
              intro: discussion.body,
              section: ::Api::Internal::Twirp::Support::HelpHub.community_forum_categories.find { |e| e.id == discussion.discussion_category_id }&.slug,
              labels: [],
              url: discussion.url,
              author: {
                avatar_url: discussion.user&.primary_avatar_url,
                display_login: discussion.user&.display_login,
              },
              upvote_count: discussion.total_upvotes,
              reaction_count: discussion.reactions_count&.values&.sum || 0,
              comment_count: discussion.comment_count,
              participant_count: discussion.participants&.count || 0,
            }
          end
        end
      end
    end
  end
end
