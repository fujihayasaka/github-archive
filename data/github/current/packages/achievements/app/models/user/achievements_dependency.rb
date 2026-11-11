# typed: false
# frozen_string_literal: true

module User::AchievementsDependency
  extend ActiveSupport::Concern
  include GitHub::Memoizer
  include GitHub::BatchMethod

  included do
    has_many :achievements, dependent: :destroy
    has_many :achievement_progressions, dependent: :destroy

    # Public: API- and .prefill_associations- friendly method to efficiently fetch the highest-tier Achievements for
    # a batch of Users, respecting all of their individual show_private_contribution settings.
    #
    # Batch methods cannot accept additional arguments, so in contrast with #highest_tier_achievements, this method
    # does not allow you to override any Users' private contribution settings, and it will return Achievements which
    # have been #hidden? by the unlocking User.
    batch_method(:visible_highest_tier_achievements) do |users|
      users_by_visibility = Hash.new { |h, k| h[k] = [] }

      visibility_promises = users.map do |user|
        user.profile_settings.async_show_private_contribution_count?.then do |show_private|
          users_by_visibility[show_private] << user
        end
      end
      Promise.all(visibility_promises).sync

      achievements_by_user = Hash.new { |h, k| h[k] = [] }
      users_by_visibility.each do |show_private, users|
        visibility = show_private ? :private_scope : :public_scope
        achievements = Achievement
          .where(user_id: users.map(&:id), visibility: visibility)
          .order(tier: :desc)
        GitHub::PrefillAssociations.prefill_associations(achievements, :user, available_records: users)

        achievements.group_by { |ach| [ach.user, ach.achievable_slug] }.each do |(user, _), achievements|
          achievements_by_user[user] << achievements.first
        end
      end

      achievements_by_user.transform_values do |achievements|
        achievements.sort_by(&:unlocked_at).reverse
      end
    end
  end

  memoize def profile_settings_visibility
    if profile_settings.show_private_contribution_count?
      :PRIVATE
    else
      :PUBLIC
    end
  end

  def achievements_for(achievable_class, visibility: profile_settings_visibility, viewer: nil)
    scope = achievements
    scope = scope.visible unless viewer == self

    scope.with_visibility(visibility).with_slug(achievable_class.slug)
  end

  def has_achievement?(achievable_class, visibility: profile_settings_visibility)
    achievements_for(achievable_class, visibility: visibility).exists?
  end

  def has_achievement_with_tier?(achievable_class, tier, visibility: profile_settings_visibility)
    achievements_for(achievable_class, visibility: visibility).with_tier(tier).exists?
  end

  def achievement_tier_for(achievable_class, visibility: profile_settings_visibility)
    highest_tier_achievement_for(achievable_class, visibility: visibility)&.tier || -1
  end

  def highest_tier_achievement_for(achievable_class, visibility: profile_settings_visibility, viewer: nil)
    achievements_for(achievable_class, visibility: visibility, viewer: viewer).order(tier: :desc).first
  end

  # Public: Return the highest-tier Achievement record associated with each unique Achievable, ordered with the
  # most-recently unlocked first.
  #
  # Returns an Array of Achievements.
  def highest_tier_achievements(visibility: profile_settings_visibility, viewer: nil)
    scope = achievements.with_visibility(visibility)
    scope = scope.visible unless viewer == self

    scope.
      order(tier: :desc).
      group_by(&:achievable_slug).
      map { |_, achievements| achievements.first }.
      sort_by(&:unlocked_at).
      reverse
  end

  # Public: Return two groups of highest-tier earned Achievements, ordered by descending unlocking time: public ones
  # and private ones. Like calling [user.highest_tier_achievements(:PUBLIC), user.highest_tier_achievements(:PRIVATE)]
  # but gets everything with a single SQL query.
  #
  # Returns a two-element Array of Arrays of Achievements.
  def all_highest_tier_achievements(viewer: nil)
    scope = achievements
    scope = scope.visible unless viewer == self
    all_achievements = scope.order(tier: :desc).partition(&:public_scope?)

    all_achievements.map do |achievements|
      achievements.
        group_by(&:achievable_slug).
        map { |_, achievements| achievements.first }.
        sort_by(&:unlocked_at).
        reverse
    end
  end

  # Public: Return the achievement progression record for the given Achievable
  #
  # Returns an AchievementProgression record
  def achievement_progression_for(achievable_class)
    progression = achievement_progressions.find_by(achievable_slug: achievable_class.slug) ||
      achievement_progressions.new(achievable_slug: achievable_class.slug)
  end
end
