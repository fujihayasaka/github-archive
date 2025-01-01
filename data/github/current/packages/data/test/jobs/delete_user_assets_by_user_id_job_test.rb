# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class DeleteUserAssetsByUserIdJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @user = create(:user, login: "leonardovillela")
    3.times do
      create(:user_asset, uploader: @user)
    end
    @last_user_asset = UserAsset.last

    @monalisa = create(:user, login: "monalisa")
    create(:user_asset, uploader: @monalisa)
  end

  test "retries on job dirty exit" do
    assert_retry_on_dirty_exit(job: DeleteUserAssetsByUserIdJob)
  end

  test "retries on recoverable exceptions" do
    assert_retry_on_recoverable_exceptions(job: DeleteUserAssetsByUserIdJob)
  end

  test "retries on database throttle" do
    assert_retry_on_throttler_error(job: DeleteUserAssetsByUserIdJob, args: [{ user_id: @user.id }], using_kwargs: true)
  end

  context "#perform" do
    context "purge user assets from CDN" do
      test "enqueue another job to purge user assets from CDN when running on dotcom" do
        assert_enqueued_with(job: PurgeFastlyUrlJob) do
          DeleteUserAssetsByUserIdJob.perform_now(user_id: @user.id)
        end
      end

      test "does not enqueue job to purge user assets from CDN when running on enterprise" do
        on_enterprise do
          GitHub.stubs(:storage_cluster_enabled?).returns(true)

          assert_no_enqueued_jobs do
            DeleteUserAssetsByUserIdJob.perform_now(user_id: @user.id)
          end
        end
      end

      test "does not enqueue job to purge user assets from CDN when running on multi-tenant(proxima)" do
        on_multi_tenant_enterprise do
          assert_no_enqueued_jobs do
            DeleteUserAssetsByUserIdJob.perform_now(user_id: @user.id)
          end
        end
      end
    end

    context "deletes by user_id" do
      test "deletes all associated user assets" do
        assert_difference(-> { UserAsset.count } => -3) do
          DeleteUserAssetsByUserIdJob.perform_now(user_id: @user.id)
        end

        refute UserAsset.exists?(@last_user_asset.id)
      end

      test "does not delete other user assets" do
        assert_no_difference(-> { UserAsset.where(user_id: @monalisa.id).count }) do
          DeleteUserAssetsByUserIdJob.perform_now(user_id: @user.id)
        end
      end
    end

    context "deletes by assets_ids" do
      test "deletes all user assets by ids" do
        assert_difference(-> { UserAsset.count } => -1) do
          DeleteUserAssetsByUserIdJob.perform_now(user_id: @user.id, assets_ids: [@last_user_asset.id])
        end

        refute UserAsset.exists?(@last_user_asset.id)
      end

      test "does not delete user assets with other ids" do
        assert_no_difference(-> { UserAsset.where(user_id: @monalisa.id).count }) do
          DeleteUserAssetsByUserIdJob.perform_now(user_id: @user.id, assets_ids: [@last_user_asset.id])
        end
      end

      test "does not raise errors when asset does not exist or was already deleted" do
        UserAsset.delete_all

        assert_nothing_raised do
          DeleteUserAssetsByUserIdJob.perform_now(user_id: @user.id, assets_ids: [@last_user_asset.id])
        end
      end
    end
  end
end
