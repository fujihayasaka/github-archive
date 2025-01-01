# typed: true
# frozen_string_literal: true

# Public: Queries useful for ranking users
# based on their recent discussion activity for a given repository.
class DiscussionLeaderboard
  RECENT_TIME_PERIOD = 30.days

  sig { params(repository: T.untyped, viewer: T.untyped).void }
  def initialize(repository:, viewer:)
    @repository = repository
    @viewer = viewer
  end

  # Public: Which users have recently contributed the most answers to this repo, and how many did they contribute?
  #
  # limit - The maximum number of users to return
  #
  # Returns a hash of User to Integer representing the count of recent answers by that User
  sig { params(limit: T.untyped).returns(T.untyped) }
  def top_answer_counts(limit:)
    measure_time "top_answer_counts" do
      users_to_answer_counts(limit: limit)
    end
  end

  private

  attr_reader :repository, :viewer

  def users_to_answer_counts(limit:)
    user_ids_to_answer_counts = measure_time "top_answer_counts.aggregation" do
      repository
        .discussion_comments
        .chosen_answers
        .where("discussion_comments.created_at >= ?", RECENT_TIME_PERIOD.ago)
        .filter_spam_for(viewer)
        .group(:user_id)
        .order(count_all: :desc)
        .limit(limit)
        .count(:all)
    end

    transform_ids_to_users(user_ids_to_answer_counts)
  end

  # Private: Transform a hash of user id keys to have User keys.
  #
  # user_ids_to_counts - Hash of User ID (Integer) to counts (Integer)
  #
  # Returns a new Hash of User to counts (Integer)
  def transform_ids_to_users(user_ids_to_counts)
    new_users_by_id = measure_time "transform_users.private_profiles_filtered" do
      User.with_visible_profiles_for(viewer).where(id: user_ids_to_counts.keys).index_by(&:id)
    end

    user_ids_to_counts.keep_if { |key, _| new_users_by_id.keys.include?(key) }
    user_ids_to_counts.transform_keys { |user_id| new_users_by_id[user_id] }
  end

  def measure_time(key)
    GitHub.dogstats.time "discussions.leaderboard.#{key}" do
      yield
    end
  end
end
