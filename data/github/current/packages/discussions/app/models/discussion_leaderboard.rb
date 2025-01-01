# typed: true
# frozen_string_literal: true

# Public: Queries useful for ranking users
# based on their recent discussion activity for a given repository.
class DiscussionLeaderboard
  include GitHub::Memoizer

  RECENT_TIME_PERIOD = 30.days
  MOST_HELPFUL_ANSWERS_LIMIT = 10

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
      scoped_comments = recent_discussion_answer_comments
      user_ids = scoped_comments.distinct.pluck(:user_id)
      return {} if user_ids.empty?

      allowed_user_ids = allowed_user_ids_from(user_ids)
      return {} if allowed_user_ids.empty?

      scoped_comments
        .for_user(allowed_user_ids)
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
      User.where(id: user_ids_to_counts.keys)
          .index_by(&:id)
    end

    user_ids_to_counts.keep_if { |key, _| new_users_by_id.keys.include?(key) }
    user_ids_to_counts.transform_keys { |user_id| new_users_by_id[user_id] }
  end

  def recent_discussion_answer_comments
    measure_time "discussion_comments.fetch" do
      repository
        .discussion_comments
        .not_posted_as_admin
        .chosen_answers
        .where("discussion_comments.created_at >= ?", RECENT_TIME_PERIOD.ago)
        .filter_spam_for(viewer)
    end
  end

  # Get allowed users, excluding staff, private profiles and Bot Users
  def allowed_user_ids_from(user_ids)
    measure_time "discussion_comments.filter_role_and_public_profiles" do
      scoped_user_ids = user_ids - staff_user_ids
      User.where(type: "User")
        .with_visible_profiles_for(viewer)
        .where(id: scoped_user_ids)
        .pluck(:id)
    end
  end

  sig { returns T::Array[Integer] }
  memoize def staff_user_ids
    return [] if GitHub.enterprise?

    employees_team = Team.with_org_name_and_slug("github", "Employees")
    return [] if employees_team.blank?

    employees_team.member_ids
  end

  def measure_time(key)
    GitHub.dogstats.time "discussions.leaderboard.#{key}" do
      yield
    end
  end
end
