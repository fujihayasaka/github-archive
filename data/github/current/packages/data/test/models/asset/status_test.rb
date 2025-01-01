# typed: true
# frozen_string_literal: true

require "test_helper"

class AssetStatusTest < GitHub::TestCase
  include GitHub::BillingTest

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @media_user = create(:credit_card_user, plan: "pro")

    @now = Time.utc(2021, 01, 10)

    GitHub.config.enable "git-lfs", @media_user
  end

  setup do
    deliveries.clear
  end

  def deliveries
    ActionMailer::Base.deliveries
  end

  test "created from user" do
    assert @media_user.git_lfs_enabled?
    status = Asset::Status.new(owner: @media_user)
    assert_valid status
    status.save!
    assert_equal status, @media_user.asset_status.reload
  end

  test "build for user" do
    assert @media_user.git_lfs_enabled?
    assert_nil @media_user.asset_status
    Asset::Status.build_for_owner(:lfs, @media_user.id)
    assert_kind_of Asset::Status, @media_user.reload.asset_status
  end

  test "non lfs asset status isn't on user" do
    assert @media_user.git_lfs_enabled?
    assert_nil @media_user.asset_status
    Asset::Status.build_for_owner(:registry, @media_user.id)
    assert_nil @media_user.reload.asset_status
  end

  test "#update_data_packs changes user's data pack count" do
    status = Asset::Status.create!(owner: @media_user)
    status.update_data_packs(quantity: 2, actor: @media_user)

    assert_equal 2, status.reload.asset_packs
  end

  test "#update_data_packs only accepts valid numbers" do
    status = Asset::Status.create!(owner: @media_user)
    perform_enqueued_jobs do # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      assert_raises ActiveRecord::RecordInvalid do
        status.update_data_packs(quantity: -3, actor: @media_user)
      end
    end
  end

  test "#update_data_packs re-enables if new packs cover usage" do
    status = Asset::Status.create!(owner: @media_user, bandwidth_down: 2.0)
    @media_user.disable_git_lfs(@media_user)
    Timecop.freeze(@now) do
      status.update_data_packs(quantity: 2, actor: @media_user)
    end

    assert_equal 2, status.reload.asset_packs
    assert @media_user.git_lfs_enabled?
    assert_equal @now, status.updated_at
  end

  test "#update_data_packs for non-lfs status does not affect lfs enabled status" do
    status = Asset::Status.create!(
      asset_type: :registry,
      owner: @media_user,
      bandwidth_down: 2.0,
    )
    @media_user.disable_git_lfs(@media_user)
    status.update_data_packs(quantity: 2, actor: @media_user)

    assert_equal 2, status.reload.asset_packs
    refute @media_user.git_lfs_enabled?
  end

  test "#update_data_packs delays downgrade of packs" do
    status = Asset::Status.create!(owner: @media_user, data_packs: 4, asset_packs: 4)

    assert_difference "Billing::PendingPlanChange.count", 1 do
      status.update_data_packs(quantity: 2, actor: @media_user)
    end

    change = @media_user.pending_plan_changes.last
    assert_equal 4, status.reload.data_packs
    assert_equal 2, change.data_packs
  end

  test "#update_data_packs allows forced downgrades" do
    status = Asset::Status.create!(owner: @media_user, data_packs: 4, asset_packs: 4)

    assert_no_difference "Billing::PendingPlanChange.count" do
      status.update_data_packs(quantity: 2, actor: @media_user, force: true)
    end

    assert_equal 2, status.reload.asset_packs
  end

  test "#update_data_packs updates pending change when upgrading" do
    status = Asset::Status.create!(owner: @media_user, data_packs: 4, asset_packs: 4)
    change = create :billing_pending_plan_change,
      user: @media_user,
      data_packs: 2

    assert_no_difference "Billing::PendingPlanChange.count" do
      status.update_data_packs(quantity: 6, actor: @media_user, force: true)
    end

    assert_equal 6, status.reload.asset_packs
    assert_equal 6, change.reload.data_packs
  end

  test "#rebuild" do
    status = T.cast(nil, T.nilable(Asset::Status))

    @media_user.plan_duration = "year"
    assert_equal true, @media_user.yearly_plan?

    Timecop.freeze(@now) do
      # start of billing cycle
      Asset::Activity.create(bandwidth_up: 0.1,
                            bandwidth_down: 0.2,
                            owner_id: @media_user,
                            activity_started_at: @media_user.first_day_in_lfs_cycle.to_time.utc + 1.second,
                            asset_type: :lfs)
      # end of billing cycle
      Asset::Activity.create(bandwidth_up: 1.0,
                            bandwidth_down: 2.0,
                            owner_id: @media_user,
                            activity_started_at: @now - 1.second,
                            asset_type: :lfs)
      # somewhere in the middle of the billing cycle
      Asset::Activity.create(bandwidth_up: 10.0,
                            bandwidth_down: 20.0,
                            owner_id: @media_user,
                            activity_started_at: @now - 3.days,
                            asset_type: :lfs)
      # it's in the middle of the billing cycle and ensures we sum up values from different months
      Asset::Activity.create(bandwidth_up: 100.0,
                            bandwidth_down: 200.0,
                            owner_id: @media_user,
                            activity_started_at: @now - 4.months,
                            asset_type: :lfs)
      # timestamp of first_day_in_lfs_cycle is inside the billing cycle
      Asset::Activity.create(bandwidth_up: 1000.0,
                            bandwidth_down: 2000.0,
                            owner_id: @media_user,
                            activity_started_at: @media_user.first_day_in_lfs_cycle.to_time.utc,
                            asset_type: :lfs)
      # now is outside the billing cycle
      Asset::Activity.create(bandwidth_up: 10000.0,
                            bandwidth_down: 20000.0,
                            owner_id: @media_user,
                            activity_started_at: @now,
                            asset_type: :lfs)
      # only asset types lfs should be considered
      Asset::Activity.create(bandwidth_up: 100000.0,
                            bandwidth_down: 200000.0,
                            owner_id: @media_user,
                            activity_started_at: @now - 2.days,
                            asset_type: :registry)
      status = Asset::Status.create(owner: @media_user)
      status.rebuild
    end

    status = T.must(status)

    assert_equal 1111.1, status.reload.bandwidth_up
    assert_equal 2222.2, status.reload.bandwidth_down
    assert_equal @now, status.updated_at
  end

  test "#rebuild resets notified state even when skipping notify" do
    return if GitHub.flipper[:lfs_disable_datapacks].enabled?
    bandwidth = 0.125
    Asset::Activity.create(bandwidth_up: 0,
                           bandwidth_down: bandwidth,
                           owner_id: @media_user,
                           activity_started_at: 3.days.ago,
                           asset_type: :lfs)
    Asset::Activity.create(bandwidth_up: bandwidth,
                           bandwidth_down: bandwidth,
                           owner_id: @media_user,
                           activity_started_at: 2.days.ago,
                           asset_type: :registry)
    status = Asset::Status.create(owner: @media_user, bandwidth_down: 100.0, data_packs: 1)
    status.check_quotas_and_notify
    assert_equal "disabled_over_quota", status.reload.notified_state
    status.rebuild(skip_notify: true)
    assert_equal "none", status.reload.notified_state

    assert_equal bandwidth, status.reload.bandwidth_down
    assert_equal 0, status.reload.bandwidth_up
  end

  test "#calculate_storage with lfs asset status" do
    b = Media::Blob.upload(create(:repository, owner: @media_user),
      "e9634919a7ce5e696812e13648c764c6ef557cddfd9c0dcce9ac7cc3d55193e0",
      {
        pusher: @media_user,
        size: 173741823,
      },
    )
    b.set_verified_state!

    Asset::Status.delete_all
    status = Asset::Status.create!(asset_type: :lfs, owner: @media_user)
    assert_equal 0.16, status.calculate_storage.round(2)
    assert_equal 0.16, status.storage.round(2)
  end

  test "#calculate_storage with registry asset status" do
    b = Media::Blob.upload(create(:repository, owner: @media_user),
      "e9634919a7ce5e696812e13648c764c6ef557cddfd9c0dcce9ac7cc3d55193e0",
      {
        pusher: @media_user,
        size: 173741823,
      },
    )
    b.set_verified_state!

    Asset::Status.delete_all
    registry_status = Asset::Status.create!(asset_type: :registry, owner: @media_user)
    assert_equal 0, registry_status.calculate_storage
    assert_equal 0, registry_status.storage
  end

  context "#send_quota_notification" do
    test "sends email for different quota limit states" do
      return if GitHub.flipper[:lfs_disable_datapacks].enabled?
      [:approaching_quota, :over_quota].each do |state|
        asset_status = create(:asset_status, bandwidth_down: 0.8, storage: 0)
        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          asset_status.send_quota_notification(state: state)
        end

        assert_equal 1, deliveries.size
        assert asset_status.reload.notified_at
        assert_equal state.to_s, asset_status.reload.notified_state

        deliveries.clear
      end
    end

    test "sends email and disables lfs when way over quota" do
      return if GitHub.flipper[:lfs_disable_datapacks].enabled?
      asset_status = create(:asset_status, bandwidth_down: 0.8, storage: 0)
      assert_performed_email(mailer: "AssetStatusMailer", action: "over_quota_disable", args: [asset_status]) do
        asset_status.send_quota_notification(state: :disabled_over_quota)

        assert_equal 1, deliveries.size
        assert asset_status.reload.notified_at
        assert_equal "disabled_over_quota", asset_status.reload.notified_state
        refute asset_status.owner.git_lfs_enabled?
      end
    end

    test "no email for other states" do
      [:none, :disabled_abuse].each do |state|
        asset_status = create(:asset_status, bandwidth_down: 0.8, storage: 0)
        asset_status.send_quota_notification(state: state)
        assert_equal 0, deliveries.size
      end
    end

    test "only sends email once" do
      return if GitHub.flipper[:lfs_disable_datapacks].enabled?
      asset_status = create(:asset_status, bandwidth_down: 0.8, storage: 0)
      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        asset_status.send_quota_notification(state: :approaching_quota)
        asset_status.send_quota_notification(state: :approaching_quota)
      end
      assert_equal 1, deliveries.size
    end

    test "raises if passed invalid state" do
      return if GitHub.flipper[:lfs_disable_datapacks].enabled?
      assert_raises ArgumentError do
        asset_status = create(:asset_status, bandwidth_down: 0.8, storage: 0)
        asset_status.send_quota_notification(state: :not_a_state)
      end
    end
  end

  context "quota checks" do
    test "skips on enterprise" do
      Asset::Status.build_for_owner(:lfs, @media_user.id)
      assert status = Asset::Status.last
      assert_equal @media_user, T.must(status).owner
      assert T.must(status).lfs?
      if GitHub.enterprise? || GitHub.flipper[:lfs_disable_datapacks].enabled?
        assert T.must(status).skip_quota_check?
      else
        refute T.must(status).skip_quota_check?
      end
    end

    test "skips for non-lfs" do
      Asset::Status.build_for_owner(:registry, @media_user.id)
      assert status = Asset::Status.last
      assert_equal @media_user, T.must(status).owner
      assert T.must(status).registry?
      assert T.must(status).skip_quota_check?
    end

    test "approaching_quota of free tier" do
      asset_status = create(:asset_status, bandwidth_down: 0.8, storage: 0)
      assert asset_status.approaching_bandwidth_quota?
      refute media_blob_over_quota?(asset_status) unless GitHub.enterprise?

      refute asset_status.approaching_storage_quota?
      refute asset_status.over_bandwidth_quota?
      refute asset_status.over_storage_quota?
      refute asset_status.over_bandwidth_quota_needs_disabling?
      refute asset_status.over_storage_quota_needs_disabling?

      asset_status = create(:asset_status, storage: 0.8, bandwidth_down: 0)
      assert asset_status.approaching_storage_quota?
      refute media_blob_over_quota?(asset_status) unless GitHub.enterprise?

      refute asset_status.approaching_bandwidth_quota?
      refute asset_status.over_bandwidth_quota?
      refute asset_status.over_storage_quota?
      refute asset_status.over_bandwidth_quota_needs_disabling?
      refute asset_status.over_storage_quota_needs_disabling?
    end

    test "approaching_quota of paid tier" do
      asset_status = create(:asset_status, bandwidth_down: 40, storage: 0, asset_packs: 1)
      assert asset_status.approaching_bandwidth_quota?
      refute media_blob_over_quota?(asset_status) unless GitHub.enterprise?

      refute asset_status.approaching_storage_quota?
      refute asset_status.over_bandwidth_quota?
      refute asset_status.over_storage_quota?
      refute asset_status.over_bandwidth_quota_needs_disabling?
      refute asset_status.over_storage_quota_needs_disabling?

      asset_status = create(:asset_status, storage: 40, bandwidth_down: 0, asset_packs: 1)
      assert asset_status.approaching_storage_quota?
      refute media_blob_over_quota?(asset_status) unless GitHub.enterprise?

      refute asset_status.approaching_bandwidth_quota?
      refute asset_status.over_bandwidth_quota?
      refute asset_status.over_storage_quota?
      refute asset_status.over_bandwidth_quota_needs_disabling?
      refute asset_status.over_storage_quota_needs_disabling?

      org = create(:invoiced_organization)
      asset_status = create(:asset_status, owner: org, bandwidth_down: 40, storage: 0, asset_packs: 1)
      refute media_blob_over_quota?(asset_status) unless GitHub.enterprise?

      refute asset_status.approaching_storage_quota?
      refute asset_status.approaching_bandwidth_quota?
      refute asset_status.over_bandwidth_quota?
      refute asset_status.over_storage_quota?
      refute asset_status.over_bandwidth_quota_needs_disabling?
      refute asset_status.over_storage_quota_needs_disabling?

      org = create(:invoiced_organization)
      asset_status = create(:asset_status, owner: org, storage: 40, bandwidth_down: 0, asset_packs: 1)
      refute media_blob_over_quota?(asset_status) unless GitHub.enterprise?

      refute asset_status.approaching_bandwidth_quota?
      refute asset_status.approaching_storage_quota?
      refute asset_status.over_bandwidth_quota?
      refute asset_status.over_storage_quota?
      refute asset_status.over_bandwidth_quota_needs_disabling?
      refute asset_status.over_storage_quota_needs_disabling?
    end

    test "over_quota of free tier" do
      asset_status = create(:asset_status, bandwidth_down: 1.1, storage: 0)
      assert asset_status.over_bandwidth_quota?
      assert media_blob_over_quota?(asset_status) unless GitHub.enterprise? || GitHub.flipper[:lfs_disable_datapacks].enabled?

      refute asset_status.over_storage_quota?
      refute asset_status.approaching_bandwidth_quota?
      refute asset_status.approaching_storage_quota?
      refute asset_status.over_bandwidth_quota_needs_disabling?
      refute asset_status.over_storage_quota_needs_disabling?

      asset_status = create(:asset_status, storage: 1.1, bandwidth_down: 0)
      assert asset_status.over_storage_quota?
      assert media_blob_over_quota?(asset_status) unless GitHub.enterprise? || GitHub.flipper[:lfs_disable_datapacks].enabled?

      refute asset_status.over_bandwidth_quota?
      refute asset_status.approaching_bandwidth_quota?
      refute asset_status.approaching_storage_quota?
      refute asset_status.over_bandwidth_quota_needs_disabling?
      refute asset_status.over_storage_quota_needs_disabling?
    end

    test "over_quota of paid tier" do
      asset_status = create(:asset_status, bandwidth_down: 50.1, storage: 0, asset_packs: 1)
      assert asset_status.over_bandwidth_quota?
      assert media_blob_over_quota?(asset_status) unless GitHub.enterprise? || GitHub.flipper[:lfs_disable_datapacks].enabled?

      refute asset_status.over_storage_quota?
      refute asset_status.approaching_bandwidth_quota?
      refute asset_status.approaching_storage_quota?
      refute asset_status.over_bandwidth_quota_needs_disabling?
      refute asset_status.over_storage_quota_needs_disabling?

      asset_status = create(:asset_status, storage: 50.1, bandwidth_down: 0, asset_packs: 1)
      assert asset_status.over_storage_quota?
      assert media_blob_over_quota?(asset_status) unless GitHub.enterprise? || GitHub.flipper[:lfs_disable_datapacks].enabled?

      refute asset_status.over_bandwidth_quota?
      refute asset_status.approaching_bandwidth_quota?
      refute asset_status.approaching_storage_quota?
      refute asset_status.over_bandwidth_quota_needs_disabling?
      refute asset_status.over_storage_quota_needs_disabling?

      org = create(:invoiced_organization)
      asset_status = create(:asset_status, owner: org, bandwidth_down: 50.1, storage: 0, asset_packs: 1)
      refute media_blob_over_quota?(asset_status) unless GitHub.enterprise? || GitHub.flipper[:lfs_disable_datapacks].enabled?

      refute asset_status.over_storage_quota?
      refute asset_status.over_bandwidth_quota?
      refute asset_status.approaching_bandwidth_quota?
      refute asset_status.approaching_storage_quota?
      refute asset_status.over_bandwidth_quota_needs_disabling?
      refute asset_status.over_storage_quota_needs_disabling?

      org = create(:invoiced_organization)
      asset_status = create(:asset_status, owner: org, storage: 50.1, bandwidth_down: 0, asset_packs: 1)
      refute media_blob_over_quota?(asset_status) unless GitHub.enterprise? || GitHub.flipper[:lfs_disable_datapacks].enabled?

      refute asset_status.over_bandwidth_quota?
      refute asset_status.over_storage_quota?
      refute asset_status.approaching_bandwidth_quota?
      refute asset_status.approaching_storage_quota?
      refute asset_status.over_bandwidth_quota_needs_disabling?
      refute asset_status.over_storage_quota_needs_disabling?
    end

    test "paid tier with invoiced user at 150% (not disabled)" do
      org = create(:invoiced_organization)
      asset_status = create(:asset_status, owner: org, bandwidth_down: 75.0, storage: 0, asset_packs: 1)

      refute media_blob_over_quota?(asset_status) unless GitHub.enterprise? || GitHub.flipper[:lfs_disable_datapacks].enabled?

      refute asset_status.over_bandwidth_quota?
      refute asset_status.approaching_bandwidth_quota?
      refute asset_status.over_storage_quota?
      refute asset_status.approaching_storage_quota?
      refute asset_status.over_bandwidth_quota_needs_disabling?
      refute asset_status.over_storage_quota_needs_disabling?

      org = create(:invoiced_organization)
      asset_status = create(:asset_status, owner: org, storage: 75.0, bandwidth_down: 0, asset_packs: 1)
      refute media_blob_over_quota?(asset_status) unless GitHub.enterprise? || GitHub.flipper[:lfs_disable_datapacks].enabled?

      refute asset_status.over_bandwidth_quota?
      refute asset_status.over_storage_quota?
      refute asset_status.approaching_bandwidth_quota?
      refute asset_status.approaching_storage_quota?
      refute asset_status.over_bandwidth_quota_needs_disabling?
      refute asset_status.over_storage_quota_needs_disabling?
    end

    test "paid tier with GitHub at 150% (not disabled)" do
      skip if GitHub.enterprise?

      org = create(:organization, login: "github")
      asset_status = create(:asset_status, owner: org, bandwidth_down: 75.0, storage: 0, asset_packs: 1)
      refute media_blob_over_quota?(asset_status)

      refute asset_status.over_bandwidth_quota?
      refute asset_status.over_storage_quota?
      refute asset_status.approaching_bandwidth_quota?
      refute asset_status.approaching_storage_quota?
      refute asset_status.over_bandwidth_quota_needs_disabling?
      refute asset_status.over_storage_quota_needs_disabling?

      asset_status.destroy!

      asset_status = create(:asset_status, owner: org, storage: 75.0, bandwidth_down: 0, asset_packs: 1)
      refute media_blob_over_quota?(asset_status)

      refute asset_status.over_bandwidth_quota?
      refute asset_status.over_storage_quota?
      refute asset_status.approaching_bandwidth_quota?
      refute asset_status.approaching_storage_quota?
      refute asset_status.over_bandwidth_quota_needs_disabling?
      refute asset_status.over_storage_quota_needs_disabling?
    end

    test "over_quota_needs_disabling of free tier" do
      asset_status = create(:asset_status, bandwidth_down: 1.5, storage: 0)
      assert asset_status.over_bandwidth_quota_needs_disabling?
      assert media_blob_over_quota?(asset_status) unless GitHub.enterprise? || GitHub.flipper[:lfs_disable_datapacks].enabled?

      refute asset_status.over_storage_quota_needs_disabling?
      refute asset_status.over_bandwidth_quota?
      refute asset_status.over_storage_quota?
      refute asset_status.approaching_bandwidth_quota?
      refute asset_status.approaching_storage_quota?

      asset_status = create(:asset_status, storage: 1.5, bandwidth_down: 0)
      assert asset_status.over_storage_quota_needs_disabling?
      assert media_blob_over_quota?(asset_status) unless GitHub.enterprise? || GitHub.flipper[:lfs_disable_datapacks].enabled?

      refute asset_status.over_bandwidth_quota_needs_disabling?
      refute asset_status.over_storage_quota?
      refute asset_status.over_bandwidth_quota?
      refute asset_status.approaching_bandwidth_quota?
      refute asset_status.approaching_storage_quota?
    end

    test "over_quota_needs_disabling of paid tier (non-invoiced users)" do
      asset_status = create(:asset_status, bandwidth_down: 75.0, storage: 0, asset_packs: 1)
      assert asset_status.over_bandwidth_quota_needs_disabling?
      assert media_blob_over_quota?(asset_status) unless GitHub.enterprise? || GitHub.flipper[:lfs_disable_datapacks].enabled?

      refute asset_status.over_storage_quota_needs_disabling?
      refute asset_status.over_bandwidth_quota?
      refute asset_status.over_storage_quota?
      refute asset_status.approaching_bandwidth_quota?
      refute asset_status.approaching_storage_quota?

      asset_status = create(:asset_status, storage: 75.0, bandwidth_down: 0, asset_packs: 1)
      assert asset_status.over_storage_quota_needs_disabling?
      assert media_blob_over_quota?(asset_status) unless GitHub.enterprise? || GitHub.flipper[:lfs_disable_datapacks].enabled?

      refute asset_status.over_bandwidth_quota_needs_disabling?
      refute asset_status.over_storage_quota?
      refute asset_status.over_bandwidth_quota?
      refute asset_status.approaching_bandwidth_quota?
      refute asset_status.approaching_storage_quota?
    end

    test "owner with no asset status" do
      repo = create(:repository)
      assert_nil repo.owner.asset_status
      refute Media::Blob.over_quota?(repo)
      if !GitHub.enterprise? && !GitHub.flipper[:lfs_disable_datapacks].enabled?
        assert repo.owner.reload.asset_status
      end
    end
  end

  context "asset_packs" do
    test "cost $5 each" do
      assert_equal Billing::Money.new(500), Asset::Status.data_pack_unit_price
    end

    test "built in quotas" do
      asset_status = create :asset_status
      assert_equal 1.0, asset_status.bandwidth_quota
      assert_equal 1.0, asset_status.storage_quota
    end

    test "packs are worth 50GB in additional quota" do
      asset_status = create(:asset_status, asset_packs: 1)
      assert_equal 50.0, asset_status.bandwidth_quota
      assert_equal 50.0, asset_status.storage_quota
    end

    test "#bandwidth_usage shows bandwidth down rounded to 3 digits" do
      asset_status = create(:asset_status, bandwidth_down: 1.11111)

      assert_equal 1.11, asset_status.bandwidth_usage
    end

    test "#storage_usage shows bandwidth down rounded to 3 digits" do
      asset_status = create(:asset_status, storage: 2.222)

      assert_equal 2.22, asset_status.storage_usage
    end

    test "#bandwidth_usage_percentage returns an integer percentage" do
      asset_status = create(:asset_status, bandwidth_down: 0.5)

      assert_equal 50, asset_status.bandwidth_usage_percentage
    end

    test "#storage_usage_percentage returns an integer percentage" do
      asset_status = create(:asset_status, storage: 0.25)

      assert_equal 25, asset_status.storage_usage_percentage
    end
  end

  context "#check_quotas_and_notify" do
    test "not approaching quota on the free tier" do
      [0, 0.7].each do |gb|
        asset_status = create(:asset_status, storage: gb, bandwidth_down: 0)
        asset_status.check_quotas_and_notify
        assert_equal 0, deliveries.size

        asset_status = create(:asset_status, storage: 0, bandwidth_down: gb)
        asset_status.check_quotas_and_notify
        assert_equal 0, deliveries.size
      end
    end

    test "not approaching quota on the paid tier" do
      [0, 39.1].each do |gb|
        asset_status = create(:asset_status, storage: gb, bandwidth_down: 0, asset_packs: 1)
        asset_status.check_quotas_and_notify
        assert_equal 0, deliveries.size

        asset_status = create(:asset_status, storage: 0, bandwidth_down: gb, asset_packs: 1)
        asset_status.check_quotas_and_notify
        assert_equal 0, deliveries.size
      end
    end

    test "approaching quota on the free tier" do
      return if GitHub.flipper[:lfs_disable_datapacks].enabled?
      [0.8, 1.0].each do |gb|
        asset_status = create(:asset_status, storage: 0, bandwidth_down: gb)
        assert_performed_email(mailer: "AssetStatusMailer", action: "approaching_quota", args: [asset_status]) do
          asset_status.check_quotas_and_notify
          assert_equal 1, deliveries.size
          assert_equal "approaching_quota", asset_status.reload.notified_state
          deliveries.clear
        end

        asset_status = create(:asset_status, storage: gb, bandwidth_down: 0)
        assert_performed_email(mailer: "AssetStatusMailer", action: "approaching_quota", args: [asset_status]) do
          asset_status.check_quotas_and_notify
          assert_equal 1, deliveries.size
          assert_equal "approaching_quota", asset_status.reload.notified_state
          deliveries.clear
        end
      end
    end

    test "approaching quota on the paid tier" do
      return if GitHub.flipper[:lfs_disable_datapacks].enabled?
      [40.0, 50.0].each do |gb|
        asset_status = create(:asset_status, storage: 0, bandwidth_down: gb, asset_packs: 1)
        assert_performed_email(mailer: "AssetStatusMailer", action: "approaching_quota", args: [asset_status]) do
          asset_status.check_quotas_and_notify
          assert_equal 1, deliveries.size
          assert_equal "approaching_quota", asset_status.reload.notified_state
          deliveries.clear
        end

        asset_status = create(:asset_status, storage: gb, bandwidth_down: 0, asset_packs: 1)
        assert_performed_email(mailer: "AssetStatusMailer", action: "approaching_quota", args: [asset_status]) do
          asset_status.check_quotas_and_notify
          assert_equal 1, deliveries.size
          assert_equal "approaching_quota", asset_status.reload.notified_state
          deliveries.clear
        end
      end
    end

    test "approaching quota but already notified" do
      asset_status = create(:asset_status, storage: 0, bandwidth_down: 0.8, notified_at: DateTime.now, notified_state: :approaching_quota)
      asset_status.check_quotas_and_notify
      assert_equal 0, deliveries.size
    end

    test "over quota on the free tier" do
      return if GitHub.flipper[:lfs_disable_datapacks].enabled?
      [1.1, 1.4].each do |gb|
        asset_status = create(:asset_status, storage: 0, bandwidth_down: gb)
        assert_performed_email(mailer: "AssetStatusMailer", action: "over_quota", args: [asset_status]) do
          asset_status.check_quotas_and_notify
          assert_equal 1, deliveries.size
          assert_equal "over_quota", asset_status.reload.notified_state
          deliveries.clear
        end

        asset_status = create(:asset_status, storage: gb, bandwidth_down: 0)
        assert_performed_email(mailer: "AssetStatusMailer", action: "over_quota", args: [asset_status]) do
          asset_status.check_quotas_and_notify
          assert_equal 1, deliveries.size
          assert_equal "over_quota", asset_status.reload.notified_state
          deliveries.clear
        end
      end
    end

    test "over quota on the paid tier" do
      return if GitHub.flipper[:lfs_disable_datapacks].enabled?
      [50.1, 74.9].each do |gb|
        asset_status = create(:asset_status, storage: 0, bandwidth_down: gb, asset_packs: 1)
        assert_performed_email(mailer: "AssetStatusMailer", action: "over_quota", args: [asset_status]) do
          asset_status.check_quotas_and_notify
          assert_equal 1, deliveries.size
          assert_equal "over_quota", asset_status.reload.notified_state
          deliveries.clear
        end

        asset_status = create(:asset_status, storage: gb, bandwidth_down: 0, asset_packs: 1)
        assert_performed_email(mailer: "AssetStatusMailer", action: "over_quota", args: [asset_status]) do
          asset_status.check_quotas_and_notify
          assert_equal 1, deliveries.size
          assert_equal "over_quota", asset_status.reload.notified_state
          deliveries.clear
        end
      end
    end

    test "way quota on the free tier (disable)" do
      return if GitHub.flipper[:lfs_disable_datapacks].enabled?
      [1.5, 2.0].each do |gb|
        Asset::Status.delete_all

        asset_status = create(:asset_status, storage: 0, bandwidth_down: gb)
        assert_performed_email(mailer: "AssetStatusMailer", action: "over_quota_disable", args: [asset_status]) do
          asset_status.check_quotas_and_notify
          assert_equal 1, deliveries.size
          assert_equal "disabled_over_quota", asset_status.reload.notified_state
          deliveries.clear
        end

        asset_status = create(:asset_status, storage: gb, bandwidth_down: 0)
        assert_performed_email(mailer: "AssetStatusMailer", action: "over_quota_disable", args: [asset_status]) do
          asset_status.check_quotas_and_notify
          assert_equal 1, deliveries.size
          assert_equal "disabled_over_quota", asset_status.reload.notified_state
          deliveries.clear
        end
      end
    end

    test "way over quota on the paid tier (disable)" do
      return if GitHub.flipper[:lfs_disable_datapacks].enabled?
      [75.0, 100.0].each do |gb|
        Asset::Status.delete_all

        asset_status = create(:asset_status, storage: 0, bandwidth_down: gb, asset_packs: 1)
        assert_performed_email(mailer: "AssetStatusMailer", action: "over_quota_disable", args: [asset_status]) do
          asset_status.check_quotas_and_notify
          assert_equal 1, deliveries.size
          assert_equal "disabled_over_quota", asset_status.reload.notified_state
          deliveries.clear
        end

        asset_status = create(:asset_status, storage: gb, bandwidth_down: 0, asset_packs: 1)
        assert_performed_email(mailer: "AssetStatusMailer", action: "over_quota_disable", args: [asset_status]) do
          asset_status.check_quotas_and_notify
          assert_equal 1, deliveries.size
          assert_equal "disabled_over_quota", asset_status.reload.notified_state
          deliveries.clear
        end
      end
    end

    test "reset over quota" do
      return if GitHub.flipper[:lfs_disable_datapacks].enabled?
      [75.0, 100.0].each do |gb|
        Asset::Status.delete_all

        asset_status = create(:asset_status, storage: 0, bandwidth_down: gb, asset_packs: 1)
        asset_status.check_quotas_and_notify
        assert_equal "disabled_over_quota", asset_status.reload.notified_state
        owner = asset_status.owner
        refute owner.git_lfs_enabled?

        asset_status.bandwidth_down = 1.0
        asset_status.check_quotas_and_notify
        assert_equal "none", asset_status.reload.notified_state
        assert owner.reload.git_lfs_enabled?

        asset_status = create(:asset_status, storage: gb, bandwidth_down: 0, asset_packs: 1)
        asset_status.check_quotas_and_notify
        assert_equal "disabled_over_quota", asset_status.notified_state
        owner = asset_status.owner
        refute owner.git_lfs_enabled?

        asset_status.storage = 1.0
        asset_status.check_quotas_and_notify
        asset_status.reload
        assert_equal "none", asset_status.notified_state
        assert owner.reload.git_lfs_enabled?
      end
    end

    test "does not reset in disabled_abuse state" do
      return if GitHub.flipper[:lfs_disable_datapacks].enabled?
      Asset::Status.delete_all

      asset_status = create(:asset_status, storage: 0, bandwidth_down: 1.0, asset_packs: 1)
      asset_status.notified_state = :disabled_abuse
      asset_status.check_quotas_and_notify
      assert_equal "disabled_abuse", asset_status.reload.notified_state
    end
  end

  def media_blob_over_quota?(status)
    owner = status.owner
    repo = create(:repository, owner: owner)
    refute Media::Blob.over_quota?(repo) # it's not over quota if it's not disabled
    owner.disable_git_lfs(User.first)
    Media::Blob.over_quota?(Repositories::Public.find_active!(repo.id)) # reload repo to reload User#git_lfs_enabled?
  end
end
