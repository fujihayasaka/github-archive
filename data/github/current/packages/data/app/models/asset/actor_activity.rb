# typed: true
# frozen_string_literal: true

# Asset activity log by owner and actor.
class Asset::ActorActivity < ApplicationRecord::Domain::Assets
  include Asset::Types


  # Public: User/Org that owns this asset activity.
  belongs_to :owner, class_name: "User"
  validates_presence_of :owner_id

  # Public: User that performed the asset activity.
  belongs_to :actor, class_name: "User"
  validates_presence_of :actor_id

  # Public: PublicKey that performed the asset activity.
  belongs_to :key, class_name: "PublicKey"
  validates_presence_of :key_id

  # Public: Repository on which the asset activity was performed.  May be nil/0
  # for older data.
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain
  validates_presence_of :repository_id

  # Public: Float bandwidth down in GB.
  # column :bandwidth_down
  validates_numericality_of :bandwidth_down, greater_than_or_equal_to: 0.0

  # Public: Float bandwidth up in GB.
  # column :bandwidth_up
  validates_numericality_of :bandwidth_up, greater_than_or_equal_to: 0.0

  # Public: Datetime when activity started.
  # column :activity_started_at

  # Public: Increase the bandwidth stats for an actor accessing an owner's LFS
  # data for a given repo and hour (as defined by started_at).
  def self.track(asset_type, owner_id, actor_id, key_id, repo_id, started_at, up: nil, down: nil)
    return unless up || down
    return if repo_id.to_i == 0

    bindings = {
      owner_id: owner_id,
      actor_id: actor_id,
      key_id: key_id,
      repository_id: repo_id,
      # Remove millis from "started_at" so MySQL won't round up to the next second.
      # This makes sure that objects are not "started in the future", which  will confuse
      # a few tests.
      started_at: started_at.floor,
      down: down.to_f,
      up: up.to_f,
      asset_type: self.asset_types[asset_type],
    }

    q = <<-SQL
      INSERT INTO asset_actor_activities (
        owner_id, actor_id, key_id, repository_id, activity_started_at,
        bandwidth_down, bandwidth_up, asset_type,
        created_at, updated_at
      ) VALUES (
        :owner_id, :actor_id, :key_id, :repository_id, :started_at,
        :down, :up, :asset_type,
        NOW(), NOW()
      ) ON DUPLICATE KEY UPDATE
        bandwidth_down = bandwidth_down+VALUES(bandwidth_down),
        bandwidth_up = bandwidth_up+VALUES(bandwidth_up),
        updated_at = NOW()
    SQL

    ActiveRecord::Base.connected_to(role: :writing) do
      self.connection.insert(Arel.sql(q, **bindings))
    end

    GitHub.dogstats.increment("s3_usage.actor_activities",
      tags: ["type:#{asset_type}"],
    )
  end

  # Finds all Asset::ActorActivities from a single [owner, actor, key] tuple
  # over a time period, bucketed to the hour.
  def self.fetch_for_owner_actor(asset_type, owner_id, actor_id, key_id, from, to)
    Asset::ActorActivity.
      where("activity_started_at > ? AND activity_started_at < ?", from, to).
      where(
        asset_type: Asset::ActorActivity.asset_types[asset_type],
        owner_id: owner_id,
        actor_id: actor_id,
        key_id: key_id,
      )
  end

end
