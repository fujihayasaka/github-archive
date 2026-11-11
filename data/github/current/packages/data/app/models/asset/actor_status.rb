# typed: true
# frozen_string_literal: true

# Billing cycle rollup of asset status by owner and actor.
class Asset::ActorStatus < ApplicationRecord::Domain::Assets
  include Asset::Types


  # Public: User/Org that owns this asset status.
  belongs_to :owner, class_name: "User"
  validates_presence_of :owner_id

  # Public: User that performed asset activity to generate this status.
  belongs_to :actor, class_name: "User"
  validates_presence_of :actor_id

  # Public: PublicKey that performed asset activity to generate this status.
  belongs_to :key, class_name: "PublicKey"
  validates_presence_of :key_id

  # Public: Float total bandwidth down in GB accrued in the current billing cycle.
  # column :bandwidth_down
  validates_numericality_of :bandwidth_down, greater_than_or_equal_to: 0.0

  # Public: Float total bandwidth up in GB accrued in the current billing cycle.
  # column :bandwidth_up
  validates_numericality_of :bandwidth_up, greater_than_or_equal_to: 0.0

  # Public: Reset the counters for use after a successful billing run.
  def reset
    update(bandwidth_up: 0.0, bandwidth_down: 0.0)
  end

  # Public: Boolean is this activity by an anonymous actor?
  def anonymous_actor?
    actor_id == 0 && key_id == 0
  end

  # Public: Boolean is this activity by a user, whether or not that user still
  # exists?
  def user_actor?
    actor_id != 0
  end

  # Public: Boolean is this activity by a deploy key, whether or not that deploy
  # key still exists?
  def key_actor?
    key_id != 0
  end

  # Public: Resets the counters for this Actor Status
  def rebuild
    return unless day = owner&.first_day_in_lfs_cycle
    start_of_billing_cycle = day.to_time.utc
    self.bandwidth_up = 0.0
    self.bandwidth_down = 0.0
    Asset::ActorActivity.fetch_for_owner_actor(asset_type, self.owner_id,
                                               self.actor_id, self.key_id,
                                               start_of_billing_cycle,
                                               Time.now.utc).each do |activity|
      self.bandwidth_up += activity.bandwidth_up
      self.bandwidth_down += activity.bandwidth_down
    end
    save
  end

  def self.actor_ids_for_owner_id(owner_id)
    where(owner_id: owner_id).pluck(:actor_id)
  end
end
