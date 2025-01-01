# typed: true
# frozen_string_literal: true

module User::UserRankedDependency
  extend ActiveSupport::Concern
  include UserRanked::Scope

  class_methods do
    def compute_ranked_ids(user:)
      UserActivityRankCalculator.calculate(user: user)
    end
  end

  class UserActivityRankCalculator
    USER_RANKED_WEIGHT = {
      following: 1,
      sponsoring: 2,
    }.freeze

    def self.calculate(user:)
      new(user: user).calculate
    end

    def initialize(user:)
      @user = user
      @other_user_ids = relevant_other_user_ids_for_user
    end

    def calculate
      sorted = other_user_ids.sort_by do |user_id|
        USER_RANKED_WEIGHT.keys.sum do |ranking_type|
          ranking_type_score(ranking_type, user_id: user_id)
        end
      end
      sorted.reverse
    end

    private

    attr_reader :other_user_ids, :user

    def relevant_other_user_ids_for_user
      following_ids = user.following_ids # who the user is following
      sponsoring_ids = sponsoring.keys # who the user is sponsoring
      (following_ids + sponsoring_ids).uniq
    end

    def ranking_type_score(ranking_type, user_id:)
      weight = USER_RANKED_WEIGHT[ranking_type]
      send(ranking_type).fetch(user_id, 0) * weight
    end

    def following
      @following ||= Following.follower_of(user).group(:user_id).count
    end

    def sponsoring
      @sponsoring ||= active_sponsorships_as_sponsor.group(:sponsorable_id).count
    end

    def active_sponsorships_as_sponsor
      @all_sponsoring ||= user.active_sponsorships_as_sponsor_relation
    end
  end
end
