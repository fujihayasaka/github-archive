# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module CommunityInsights
  class DiscussionsDailyContributorsJob < ApplicationJob
    PERIODS = CommunityInsightsDailyCount::PERIODS

    queue_as :discussions_daily_contributors

    retry_on_dirty_exit

    locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC


    def perform(repository_id, date)
      today_range = date.beginning_of_day..date.end_of_day
      past_year_range = date.beginning_of_day - PERIODS[:last_year]...date.beginning_of_day #excludes current date from range

      today_activity = get_distinct_users(repository_id, today_range)
      past_year_activity = get_distinct_users(repository_id, past_year_range)

      contributor_count = today_activity.length
      new_contributor_daily_count = (today_activity - past_year_activity).length

      ActiveRecord::Base.connected_to(role: :writing) do
        CommunityInsightsDailyCount.set_count(repository_id, date, :discussion_contributors_count, contributor_count)
        CommunityInsightsDailyCount.set_count(repository_id, date, :discussion_new_contributor_count, new_contributor_daily_count)
      end
    end

    private

    def get_distinct_users(repository_id, day_range)
      discussion_user_ids = Discussion.select(:user_id)
        .distinct
        .where(repository_id: repository_id, created_at: day_range)
        .filter_spam_for(nil)

      reaction_user_ids = DiscussionReaction.select(:user_id)
        .distinct
        .joins(:discussion)
        .where(discussions: { repository_id: repository_id, user_hidden: false }, created_at: day_range)

      vote_user_ids = DiscussionVote.select(:user_id)
        .distinct
        .joins(:discussion)
        .where(discussions: { repository_id: repository_id, user_hidden: false }, created_at: day_range)

      comment_user_ids = DiscussionComment.select(:user_id)
        .distinct
        .where(repository_id: repository_id, created_at: day_range)
        .filter_spam_for(nil)

      comment_reaction_user_ids = DiscussionCommentReaction.select(:user_id)
        .distinct
        .joins(:discussion_comment)
        .where(discussion_comments: { repository_id: repository_id, user_hidden: false }, created_at: day_range)

      comment_vote_user_ids = DiscussionCommentVote.select(:user_id)
        .distinct
        .joins(:comment)
        .where(comment: { repository_id: repository_id, user_hidden: false }, created_at: day_range)

      user_ids = discussion_user_ids + reaction_user_ids + vote_user_ids + comment_user_ids + comment_reaction_user_ids + comment_vote_user_ids

      user_ids.uniq
    end
  end
end
