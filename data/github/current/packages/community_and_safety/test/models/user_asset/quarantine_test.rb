# typed: false
# frozen_string_literal: true

require "test_helper"

class UserAssetQuarantineTest < GitHub::TestCase
  skip_with_all_emus
  skip_in_multitenant_mode

  include UploadableTestHelpers
  include CdnTestHelper
  include AuditLog::IntegrationTestHelpers

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
    @asset = save_file_for_uploadable(UserAsset.new(uploader: @user))
  end

  setup do
    @s3_client = Aws::S3::Client.new(stub_responses: true)

    GitHub.stubs(:s3_primary_client).returns(@s3_client)
    GitHub.stubs(:s3_production_data_client).returns(@s3_client)
    GitHub.s3_uploads_enabled = true
    GitHub.storage_cluster_enabled = false
  end

  def stub_asset_update(asset, **args)
    asset.stubs(:update).with(**args)
  end

  def stub_put_object_acl(asset, acl)
    @s3_client
      .expects(:put_object_acl)
      .with(bucket: asset.storage_s3_bucket, key: asset.storage_s3_key(nil), acl: acl)
  end

  def stub_get_original_acl(asset, desired_acl)
    private_grant = Aws::S3::Types::Grant.new(
      grantee: Aws::S3::Types::Grantee.new(type: "CanonicalUser"),
      permission: "FULL_CONTROL",
    )

    public_grant = Aws::S3::Types::Grant.new(
      grantee: Aws::S3::Types::Grantee.new(type: "Group", uri: "http://acs.amazonaws.com/groups/global/AllUsers"),
      permission: "READ",
    )

    grants = [private_grant]
    grants << public_grant if desired_acl == "public-read"

    output = Aws::S3::Types::GetObjectAclOutput.new(grants: grants)

    @s3_client
      .stubs(:get_object_acl)
      .with(bucket: asset.storage_s3_bucket, key: asset.storage_s3_key(nil))
      .returns(output)
  end

  def with_quarantining_asset(**args, &block)
    default_args = { uploader: @user, quarantining: true, repository_id: @repo.id }
    default_args = default_args.merge(args)
    asset = create(:user_asset, default_args)
    yield asset
  end

  def with_generic_quarantine_stub(&block)
    asset = create(:user_asset, uploader: @user)
    stub_get_original_acl(asset, "private")
    yield asset
  end

  context "quarantine" do
    test "doesn't quarantine if storage cluster is enabled" do
      GitHub.stubs(:storage_cluster_enabled?).returns(true)
      refute @asset.quarantine(reason: "CSAM")
    end

    test "doesn't quarantine if in multi tenant" do
      GitHub.stubs(:multi_tenant_enterprise?).returns(true)
      refute @asset.quarantine(reason: "CSAM")
    end

    test "doesn't quarantine if asset is already in quarantine" do
      with_quarantining_asset { |asset| refute asset.quarantine(reason: "CSAM") }
    end

    context "when original acl is private" do
      test "doesn't update acl" do
        asset = create(:user_asset, uploader: @user)

        stub_get_original_acl(asset, "private")

        @s3_client.expects(:put_object_acl).never

        asset.quarantine(reason: "CSAM")

        asset.reload
        assert_equal "private", asset.original_acl
        assert_equal true, asset.quarantining
      end

      test "doesn't revert acl if model update doesn't succeed" do
        asset = create(:user_asset, uploader: @user)

        stub_get_original_acl(asset, "private")

        @s3_client.expects(:put_object_acl).never

        stub_asset_update(asset, original_acl: "private", quarantining: true).returns(false)

        asset.quarantine(reason: "CSAM")
      end
    end

    context "when original acl is public-read" do
      test "updates acl to private" do
        asset = create(:user_asset, uploader: @user)

        stub_get_original_acl(asset, "public-read")

        stub_put_object_acl(asset, "private").once

        asset.quarantine(reason: "CSAM")

        asset.reload
        assert_equal "public-read", asset.original_acl
        assert_equal true, asset.quarantining
      end

      test "reverts acl to public if model update doesn't succeed" do
        asset = create(:user_asset, uploader: @user)

        original_acl = "public-read"

        stub_get_original_acl(asset, original_acl)

        stub_put_object_acl(asset, "private").once

        stub_asset_update(asset, original_acl: original_acl, quarantining: true).returns(false)

        stub_put_object_acl(asset, original_acl).once

        asset.quarantine(reason: "CSAM")
      end
    end


    test "instruments a quarantine event" do
      with_generic_quarantine_stub do |asset|
        events = subscribe "assets.quarantine"

        asset.quarantine(reason: "CSAM")

        expected_payload = {
          user_id: asset.uploader.id,
          user_asset_id: asset.id,
          reason: "CSAM",
        }

        assert event = events.pop, "user_asset.quarantine event was expected"
        assert_subset_hash expected_payload, event.payload
      end
    end

    test "instruments a quarantine event in the audit log" do
      with_generic_quarantine_stub do |asset|
        events = assert_performed_audit_entries(count: 1, only: "assets.quarantine") do
          asset.quarantine(reason: "CSAM")
        end

        expected_payload = {
          user_id: asset.uploader.id,
          user_asset_id: asset.id,
          reason: "CSAM",
        }

        assert_subset_hash expected_payload, events.first
      end
    end
  end

  context "unquarantine" do
    test "doesn't unquarantine if storage cluster is enabled" do
      GitHub.stubs(:storage_cluster_enabled?).returns(true)
      refute @asset.unquarantine(reason: "confirmed false positive")
    end

    test "doesn't unquarantine if in multi tenant" do
      GitHub.stubs(:multi_tenant_enterprise?).returns(true)
      refute @asset.unquarantine(reason: "confirmed false positive")
    end

    context "when it's legacy asset" do
      test "updates acl" do
        with_quarantining_asset(repository_id: nil, upload_container_type: nil) do |asset|
          stub_put_object_acl(asset, "public-read").once

          asset.unquarantine(reason: "confirmed false positive")

          asset.reload
          assert_nil asset.original_acl
          assert_nil asset.quarantining
        end
      end

      test "reverts acl to private if model update doesn't succeed" do
        with_quarantining_asset(repository_id: nil, upload_container_type: nil) do |asset|
          stub_put_object_acl(asset, "public-read").once

          stub_asset_update(asset, quarantining: nil).returns(false)

          stub_put_object_acl(asset, "private").once

          asset.unquarantine(reason: "confirmed false positive")
        end
      end
    end

    context "when original acl is private" do
      test "doesn't update acl" do
        with_quarantining_asset(original_acl: "private") do |asset|
          @s3_client.expects(:put_object_acl).never

          asset.unquarantine(reason: "confirmed false positive")

          asset.reload
          assert_equal "private", asset.original_acl
          assert_nil asset.quarantining
        end
      end

      test "reverts acl if model update doesn't succeed" do
        with_quarantining_asset(original_acl: "private") do |asset|
          stub_asset_update(asset, quarantining: nil).returns(false)

          stub_put_object_acl(asset, "private").once

          asset.unquarantine(reason: "confirmed false positive")
        end
      end
    end

    context "when original acl is public-read" do
      test "updates acl" do
        with_quarantining_asset(original_acl: "public-read") do |asset|
          stub_put_object_acl(asset, "public-read").once

          asset.unquarantine(reason: "confirmed false positive")

          asset.reload
          assert_equal "public-read", asset.original_acl
          assert_nil asset.quarantining
        end
      end

      test "reverts acl to private if model update doesn't succeed" do
        with_quarantining_asset(original_acl: "public-read") do |asset|
          stub_put_object_acl(asset, "public-read").once

          stub_asset_update(asset, quarantining: nil).returns(false)

          stub_put_object_acl(asset, "private").once

          asset.unquarantine(reason: "confirmed false positive")
        end
      end
    end

    test "clears CDN cache" do
      Timecop.freeze do
        with_quarantining_asset(original_acl: "private") do |asset|
          purging_urls = [asset.storage_external_url]

          asset.with_storage_provider(:default) do
            # assert reqs against old s3/fastly domains
            purging_urls << asset.storage_external_url
          end

          assert_purge_url(*purging_urls) do
            asset.unquarantine(reason: "confirmed false positive")
          end
        end
      end
    end

    test "instruments an unquarantine event" do
      with_quarantining_asset(original_acl: "private") do |asset|
        events = subscribe "assets.unquarantine"

        asset.unquarantine(reason: "confirmed false positive")

        expected_payload = {
          user_id: asset.uploader.id,
          reason: "confirmed false positive",
          user_asset_id: asset.id,
        }

        assert event = events.pop, "user_asset.unquarantine event was expected"
        assert_subset_hash expected_payload, event.payload
      end
    end

    test "instruments an unquarantine event in the audit log" do
      with_quarantining_asset(original_acl: "private") do |asset|
        events = assert_performed_audit_entries(count: 1, only: "assets.unquarantine") do
          asset.unquarantine(reason: "confirmed false positive")
        end

        expected_payload = {
          user_id: asset.uploader.id,
          user_asset_id: asset.id,
          reason: "confirmed false positive",
        }

        assert_subset_hash expected_payload, events.first
      end
    end
  end

  test "clear_from_cdn_cache clears CDN cache but doesn't delete" do
    repo = create :repository, owner: @user
    issue = create(:issue, repository: repo, user: @user)
    attachment = Attachment.create!(attacher: @user, asset: @asset,
      attachable: issue, entity: repo)

    assert_equal attachment, Attachment.find_by_id(attachment.id)
    assert_equal 1, @asset.attachments.count

    Timecop.freeze do
      purging_urls = [@asset.storage_external_url]

      @asset.with_storage_provider(:default) do
        # assert reqs against old s3/fastly domains
        purging_urls << @asset.storage_external_url
      end

      assert_purge_url(*purging_urls) do
        @asset.clear_from_cdn_cache
      end

      refute_nil Attachment.find_by_id(attachment.id)
    end
  end
end
