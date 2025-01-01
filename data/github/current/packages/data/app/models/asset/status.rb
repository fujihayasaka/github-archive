# typed: true
# frozen_string_literal: true

class Asset::Status < ApplicationRecord::Domain::Assets
  include Asset::Types

  self.table_name = :asset_statuses


  include Asset::Status::ZuoraDependency

  def self.build_for_owner(asset_type, owner_id)
    ActiveRecord::Base.connected_to(role: :writing) do
      bindings = {
        asset_type: self.asset_types[asset_type],
        owner_id: owner_id,
      }

      self.connection.insert(Arel.sql(<<-SQL, **bindings))
        INSERT INTO asset_statuses (asset_type, owner_id, created_at, updated_at)
        VALUES (:asset_type, :owner_id, NOW(), NOW())
        ON DUPLICATE KEY UPDATE updated_at = NOW()
      SQL
    end
  end

  def self.data_pack_unit_price
    # This can result in HTTP calls to update exchange rates,
    # so don't assign it to a constant to avoid HTTP calls when booting the app.
    @_data_pack_unit_price ||= Billing::Money.new(500)
  end

  DATA_PACK_BANDWIDTH  = 50.0 # GB
  DATA_PACK_STORAGE    = 50.0 # GB
  FREE_BANDWIDTH_QUOTA = 1.0  # GB
  FREE_STORAGE_QUOTA   = 1.0  # GB

  # Public: User/Org that owns this asset status.
  belongs_to :owner, class_name: "User"
  validates_presence_of :owner_id

  # Public: Float total bandwidth down in GB accrued in the current billing cycle.
  # column :bandwidth_down
  validates_numericality_of :bandwidth_down, greater_than_or_equal_to: 0.0

  # Public: Float total bandwidth up in GB accrued in the current billing cycle.
  # column :bandwidth_up
  validates_numericality_of :bandwidth_up, greater_than_or_equal_to: 0.0

  # Public: Float total storage up in GB accrued in the current billing cycle.
  # column :storage
  validates_numericality_of :storage, greater_than_or_equal_to: 0.0

  # Public: Integer number of data packs purchased by the user/org.
  # column :asset_packs
  validates_numericality_of :asset_packs, greater_than_or_equal_to: 0

  # Public: Integer number of data packs purchased by the user/org.
  # column :data_packs
  validates_numericality_of :data_packs, greater_than_or_equal_to: 0

  # Public: Enumeration of valid notified states.
  enum :notified_state, {
    none: 0,
    approaching_quota: 1, # At 80% of quota
    over_quota: 2, # At 100%+ of bandwidth quota
    disabled_over_quota: 3, # At 150% of quota, auto disabled
    disabled_abuse: 4, # Disabled due to abuse
  }, prefix: true

  validates :notified_state, presence: true

  # Public: Check usage against quotas and notify the owner if necessary. If an
  # email notification is necessary a job is queued to send the email. See
  # Asset::Status#send_quota_notification.
  #
  # Returns nothing.
  def check_quotas_and_notify(notify: true)
    return if skip_quota_check?

    current_state = if approaching_bandwidth_quota? || approaching_storage_quota?
      :approaching_quota
    elsif over_bandwidth_quota? || over_storage_quota?
      :over_quota
    elsif over_bandwidth_quota_needs_disabling? || over_storage_quota_needs_disabling?
      :disabled_over_quota
    elsif notified_state.to_sym == :disabled_abuse
      :disabled_abuse
    else
      :none
    end

    if current_state == :none
      update(notified_state: current_state)
      enable_owner_feature
    elsif notify
      send_quota_notification(state: current_state) unless notified_at && notified_state == current_state.to_s
    end
  end

  # Public: Send the owner of this asset status a notification about the state
  # of their storage/bandwidth quota.
  #
  # state - Symbol state to notify about. See notified_states.
  #
  # Returns nothing.
  def send_quota_notification(state:)
    return if skip_quota_check?

    unless self.class.notified_states[state].present?
      raise ArgumentError, "state must be one of #{self.class.notified_states.keys.inspect}"
    end

    return if notified_at && notified_state == state.to_s

    transaction do
      update(notified_at: DateTime.now,
        notified_state: state)

      case state
      when :approaching_quota
        AssetStatusMailer.approaching_quota(self).deliver_later
        GitHub.dogstats.increment("asset_status.notifications", tags: ["state:#{state}"])
      when :over_quota
        AssetStatusMailer.over_quota(self).deliver_later
        GitHub.dogstats.increment("asset_status.notifications", tags: ["state:#{state}"])
      when :disabled_over_quota
        disable_owner_feature
        AssetStatusMailer.over_quota_disable(self).deliver_later
        GitHub.dogstats.increment("asset_status.notifications", tags: ["state:#{state}"])
      end
    end
  end

  # Public: Float bandwidth quota.
  def bandwidth_quota
    monthly_quota = [FREE_BANDWIDTH_QUOTA, asset_packs * DATA_PACK_BANDWIDTH].max
    duration_in_months = async_owner.then do |owner|
      T.must(owner).plan_duration_in_months
    end.sync
    monthly_quota * duration_in_months
  end

  # Public: Float bandwidth usage.
  def bandwidth_usage
    bandwidth_down.round(2)
  end

  # Public: Integer bandwidth usage percentage
  def bandwidth_usage_percentage
    percent = (bandwidth_usage / bandwidth_quota).round(2)
    (percent * 100).to_i
  end

  # Public: Boolean if bandwidth is between 80% - 100% of quota.
  def approaching_bandwidth_quota?
    quota_state(bandwidth_quota, bandwidth_down) == :approaching_quota
  end

  # Public: Boolean if bandwidth is between 100% - 150% of quota or, if the user
  # is invoiced, even greater.
  def over_bandwidth_quota?
    quota_state(bandwidth_quota, bandwidth_down) == :over_quota
  end

  # Public: Boolean if bandwidth is between 100% - 150% of quota and the user is
  # not invoiced.
  def over_bandwidth_quota_needs_disabling?
    quota_state(bandwidth_quota, bandwidth_down) == :disabled_over_quota
  end

  # Public: Float storage quota.
  def storage_quota
    [FREE_STORAGE_QUOTA, asset_packs * DATA_PACK_STORAGE].max
  end

  # Public: Float storage usage.
  def storage_usage
    storage.round(2)
  end

  # Public: Integer storage usage percentage
  def storage_usage_percentage
    percent = (storage_usage / storage_quota).round(2)
    (percent * 100).to_i
  end

  # Public: Boolean if storage is between 80% - 100% of quota.
  def approaching_storage_quota?
    quota_state(storage_quota, storage) == :approaching_quota
  end

  # Public: Boolean if storage is between 100% - 150% of quota, or if the user
  # is invoiced, even greater.
  def over_storage_quota?
    quota_state(storage_quota, storage) == :over_quota
  end

  # Public: Boolean if storage is between 100% - 150% of quota and the user is
  # not invoiced.
  def over_storage_quota_needs_disabling?
    quota_state(storage_quota, storage) == :disabled_over_quota
  end

  # Public: Update the number of purchased data packs.
  #
  # quantity - Integer new quantity of data packs.
  # actor    - User making the change.
  #
  # Returns nothing.
  def update_data_packs(quantity:, actor:, force: false)
    old_data_packs = asset_packs
    return if old_data_packs == quantity

    # If there's no owner, then there's no point in updating that user's data
    # packs or billing information.
    acct_owner = owner
    return if acct_owner.nil?

    if !force && old_data_packs > quantity.to_i
      Billing::SchedulePlanChange.run \
        account: acct_owner,
        actor: actor,
        data_packs: quantity
    else
      # Temporarily write to both columns while we rename asset_packs to data_packs
      update!(asset_packs: quantity.to_i)
      update!(data_packs: quantity.to_i)

      # We need to update the pending plan change with the new data count
      if pending_cycle_change = acct_owner.pending_cycle_change
        pending_cycle_change.update(data_packs: quantity.to_i)
      end

      acct_owner.update_plan_with_data_packs
      acct_owner.track_data_pack_change(actor, old_data_packs: old_data_packs)

      GlobalInstrumenter.instrument(
        "billing.lfs_change",
        actor_id: actor.id,
        user_id: acct_owner.id,
        old_lfs_count: old_data_packs,
        new_lfs_count: quantity,
      )

      self.updated_at = Time.now
      save

      # Turn on Git LFS if the new data packs fully cover usage.
      if !owner_feature_enabled? &&
         !over_storage_quota? && !over_storage_quota_needs_disabling? &&
         !over_bandwidth_quota? && !over_bandwidth_quota_needs_disabling?
        enable_owner_feature
      end
    end
  end

  # Public: Resets and rebuilds Asset::Status bandwidth and storage meters
  def rebuild(skip_notify: false)
    return if owner.nil?

    self.bandwidth_up = 0.0
    self.bandwidth_down = 0.0
    start_of_billing_cycle = T.must(owner).first_day_in_lfs_cycle.to_time.utc

    # slice this in monthly chunks to avoid query interruptions
    start_time = start_of_billing_cycle
    finish = Time.now.utc
    while start_time <= finish
      end_time = start_time + 1.month + 1.day
      ActiveRecord::Base.connected_to(role: :reading) do
        # SUM() in the database to avoid returning thousands of rows for busy owners
        results = Asset::Activity.fetch_for_owner(asset_type, owner, start_time, [end_time, finish].min)
                                .pluck(Arel.sql("COALESCE(SUM(bandwidth_up), 0), COALESCE(SUM(bandwidth_down), 0)"))
        self.bandwidth_up += results.first[0]
        self.bandwidth_down += results.first[1]
      end
      start_time = end_time
    end

    calculate_storage
    self.updated_at = Time.now
    save

    check_quotas_and_notify(notify: !skip_notify)
  end

  def disabled_because_over_quota?
    !owner_feature_enabled? &&
      (over_storage_quota? || over_storage_quota_needs_disabling? ||
       over_bandwidth_quota? || over_bandwidth_quota_needs_disabling?)
  end

  # Future placeholder to block Asset access for invalid uses.
  def active?
    skip_quota_check? || !disabled_because_over_quota?
  end

  def used?
    storage_usage.nonzero? || bandwidth_usage.nonzero?
  end

  # Public: Calculates total storage consumed by the owner of this Asset::Status
  # record in GB and assigns the :storage field.
  #
  # Warning: This is a slow method and should only be called by a job.
  #
  # Returns total storage in GB.
  def calculate_storage
    self.storage = if lfs?
      Media::Blob.storage_by_owner(owner) / (1024**3).to_f
    else
      0
    end
  end

  def skip_quota_check?
    return true if ::FeatureFlag.vexi.enabled?(:cutoff_emissions_to_meuse, default: false)
    return true if GitHub.enterprise? || !lfs?
    actor = owner&.delegate_billing_to_business? ? owner&.business : owner
    actor.customer&.git_lfs_billed_on_billing_platform?
  end

  def owner_feature_enabled?
    return true if !lfs? || owner.nil?
    T.must(owner).git_lfs_enabled?
  end

  private

  def enable_owner_feature
    return if !lfs? || owner.nil?
    T.must(owner).enable_git_lfs(owner)
  end

  def disable_owner_feature
    return if !lfs? || owner.nil?
    T.must(owner).disable_git_lfs(owner)
  end

  def owner_is_github?
    !GitHub.enterprise? && owner&.login == "github"
  end

  def quota_state(quota, usage)
    if usage < 0.8 * quota || owner&.invoiced? || owner_is_github?
      :none
    elsif usage >= 0.8 * quota && usage <= quota
      :approaching_quota
    elsif usage > quota && usage < 1.5 * quota
      :over_quota
    else
      :disabled_over_quota
    end
  end
end
