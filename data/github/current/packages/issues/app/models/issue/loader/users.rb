# typed: true
# frozen_string_literal: true

class Issue::Loader::Users < Issue::Loader::Base
  def initialize(context, user_ids: [])
    @context = context
    @user_ids = user_ids
  end

  def self.load_for(context, user_ids: [])
    super new(context, user_ids: user_ids)
  end

  def load
    Issue::Loader::Users.load_users(@user_ids).tap do |users_by_id|
      @context.preload_attr(:users_by_id, users_by_id)
    end
  end

  def preload_primary_avatars_for_users(users, scope)
    track_execution_time(scope) do
      Promise.all(users.map do |user|
        next unless user

        if user.is_a?(Bot)
          # bots use integration avatars or the integration owner avatar
          T.must(user.integration).async_primary_avatar
        else
          user.async_primary_avatar
        end
      end).sync
    end
  end

  def self.load_users(user_ids)
    User.strict_loading.
      includes(:profile).
      where(id: user_ids).
      index_by(&:id)
  end

  def self.preload_bots_for(context, bots: [])
    new(context, user_ids: []).preload_bots(bots)
  end

  def preload_bots(bots)
    track_execution_time do
      Promise.all([
        async_preload_attribute(bots, :marketplace_listing_url, :async_marketplace_listing_url),
        async_preload_attribute(bots, :is_dependabot, :async_is_dependabot?),
      ]).sync
    end
  end
end
