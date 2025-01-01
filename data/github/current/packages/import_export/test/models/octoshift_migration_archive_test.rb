# typed: true
# frozen_string_literal: true

require "test_helper"

class OctoshiftMigrationArchiveTest < GitHub::TestCase
  fixtures do
    @organization = create(:organization)
    @user = create(:user)
    @octoshift_migration_archive = create(:octoshift_migration_archive, organization: @organization, uploader: @user)
  end

  setup do
    GitHub.gei_archives_blob_storage_type = nil
    GitHub.gei_archives_aws_access_key_id = "example_gei_archives_aws_access_key_id"
    GitHub.gei_archives_aws_secret_access_key = "example_gei_archives_aws_secret_access_key"
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  context ".storage_new" do
    test "returns the expected OctoshiftMigrationArchive object" do
      name = "example.tar.gz"
      content_type = "application/x-gzip"

      blob = create(:storage_blob)

      meta = {
        name: name,
        content_type: content_type,
        size: blob.size,
        oid: blob.oid,
        organization_id: @organization.id
      }

      octoshift_migration_archive = OctoshiftMigrationArchive.storage_new(@user, blob, meta)

      assert_equal name, octoshift_migration_archive.name
      assert_equal content_type, octoshift_migration_archive.content_type
      assert_equal blob.size, octoshift_migration_archive.size
      assert_equal blob.oid, octoshift_migration_archive.oid
      assert_equal @organization, octoshift_migration_archive.organization
      assert_equal @user, octoshift_migration_archive.uploader
      assert_equal "starter", octoshift_migration_archive.state
      assert_nil octoshift_migration_archive.guid
    end
  end

  context ".storage_create" do
    test "creates the expected OctoshiftMigrationArchive object" do
      name = "example.tar.gz"
      content_type = "application/x-gzip"

      blob = create(:storage_blob)

      meta = {
        name: name,
        content_type: content_type,
        size: blob.size,
        oid: blob.oid,
        organization_id: @organization.id
      }

      octoshift_migration_archive = OctoshiftMigrationArchive.storage_create(@user, blob, meta)

      assert_equal name, octoshift_migration_archive.name
      assert_equal content_type, octoshift_migration_archive.content_type
      assert_equal blob.size, octoshift_migration_archive.size
      assert_equal blob.oid, octoshift_migration_archive.oid
      assert_equal @organization, octoshift_migration_archive.organization
      assert_equal @user, octoshift_migration_archive.uploader
      assert_equal "uploaded", octoshift_migration_archive.state
      assert_match /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, octoshift_migration_archive.guid
    end
  end

  context "#guid" do
    test "returns expected GUID" do
      assert_match /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, @octoshift_migration_archive.guid
    end
  end

  context "#gei_uri" do
    test "returns expected GEI URI" do
      assert_match "gei://archive/#{@octoshift_migration_archive.guid}", @octoshift_migration_archive.gei_uri
    end
  end

  context "#set_multi_part_attributes" do
    test "sets expected values without saving the record" do
      state = :multipart_upload_started

      attributes = {
        "part_number" => "example_part_number",
        "sha256" => "example_sha256",
        "upload_id" => "example_upload_id"
      }

      @octoshift_migration_archive.expects(:save).never

      @octoshift_migration_archive.set_multi_part_attributes(state: state, attributes: attributes)

      assert_equal true, @octoshift_migration_archive.supports_multi_part_upload
      assert_equal state.to_s, @octoshift_migration_archive.state
      assert_equal attributes["part_number"], @octoshift_migration_archive.part_number
      assert_equal attributes["sha256"], @octoshift_migration_archive.part_sha
      assert_equal attributes["upload_id"], @octoshift_migration_archive.multi_part_upload_id

      assert_equal({ "state" => "starter" }, @octoshift_migration_archive.changed_attributes)
    end
  end

  context "#set_multi_part_attributes!" do
    test "sets expected values and saves the record" do
      state = :multipart_upload_started

      attributes = {
        "part_number" => "example_part_number",
        "sha256" => "example_sha256",
        "upload_id" => "example_upload_id"
      }

      @octoshift_migration_archive.set_multi_part_attributes!(state: state, attributes: attributes)

      assert_equal true, @octoshift_migration_archive.supports_multi_part_upload
      assert_equal state.to_s, @octoshift_migration_archive.state
      assert_equal attributes["part_number"], @octoshift_migration_archive.part_number
      assert_equal attributes["sha256"], @octoshift_migration_archive.part_sha
      assert_equal attributes["upload_id"], @octoshift_migration_archive.multi_part_upload_id

      assert_empty @octoshift_migration_archive.changed_attributes
    end
  end

  context "#storage_policy" do
    test "returns expected policy" do
      policy = @octoshift_migration_archive.storage_policy

      assert policy.is_a?(Storage::ClusterPolicy)
    end
  end

  context "#storage_external_url" do
    test "returns correct URL" do
      expected_url_regex = %r{\A#{GitHub.storage_cluster_url}/organizations/#{@organization.id}/gei/archive/#{@octoshift_migration_archive.guid}\?token=.+}

      assert_match expected_url_regex, @octoshift_migration_archive.storage_external_url(@user)
    end
  end

  context "#creation_url" do
    test "returns correct URL" do
      expected_url = "#{GitHub.storage_cluster_url}/organizations/#{@organization.id}/gei/archive"

      assert_equal expected_url, @octoshift_migration_archive.creation_url
    end
  end

  context "#storage_upload_path_info" do
    test "returns correct path" do
      expected_path = "/internal/storage/organizations/#{@organization.id}/gei/archive"
      policy = @octoshift_migration_archive.storage_policy

      assert_equal expected_path, @octoshift_migration_archive.storage_upload_path_info(policy)
    end
  end

  context "#storage_policy_api_url" do
    test "returns correct path" do
      expected_path = "/organizations/#{@organization.id}/gei/archive/#{@octoshift_migration_archive.guid}"

      assert_equal expected_path, @octoshift_migration_archive.storage_policy_api_url
    end
  end

  context "#storage_cluster_url" do
    test "returns correct URL" do
      expected_url = "#{GitHub.storage_cluster_url}/organizations/#{@organization.id}/gei/archive/#{@octoshift_migration_archive.guid}"
      policy = @octoshift_migration_archive.storage_policy

      assert_equal expected_url, @octoshift_migration_archive.storage_cluster_url(policy)
    end
  end

  context "#storage_download_path_info" do
    test "returns correct path" do
      expected_path = "/internal/storage/organizations/#{@organization.id}/gei/archive/#{@octoshift_migration_archive.guid}"
      policy = @octoshift_migration_archive.storage_policy

      assert_equal expected_path, @octoshift_migration_archive.storage_download_path_info(policy)
    end
  end

  context "#download_url" do
    test "returns correct URL" do
      expected_url_regex = %r{\A#{GitHub.storage_cluster_url}/organizations/#{@organization.id}/gei/archive/#{@octoshift_migration_archive.guid}\?token=.+}

      assert_match expected_url_regex, @octoshift_migration_archive.download_url(actor: @user)
    end
  end

  context "#storage_provider" do
    test "returns nil" do
      assert_nil @octoshift_migration_archive.storage_provider
    end

    context "when GitHub.gei_archives_blob_storage_type is \"s3\"" do
      test "returns :s3_gei_archives" do
        GitHub.gei_archives_blob_storage_type = "s3"

        assert_equal :s3_gei_archives, @octoshift_migration_archive.storage_provider
      end
    end
  end

  context "#storage_s3_access_key" do
    test "returns \"example_gei_archives_aws_access_key_id\"" do
      assert_equal "example_gei_archives_aws_access_key_id", @octoshift_migration_archive.storage_s3_access_key
    end
  end

  context "#storage_s3_secret_key" do
    test "returns \"example_gei_archives_aws_secret_access_key\"" do
      assert_equal "example_gei_archives_aws_secret_access_key", @octoshift_migration_archive.storage_s3_secret_key
    end
  end

  context "#storage_s3_bucket" do
    context "when in a development Rails environment" do
      test "returns \"github-development-gei-archive-23d850\"" do
        Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("development"))

        assert_equal "github-development-gei-archive-23d850", @octoshift_migration_archive.storage_s3_bucket
      end
    end

    context "when in a production Rails environment" do
      test "returns \"github-production-gei-archive-23d850\"" do
        Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("production"))

        assert_equal "github-production-gei-archive-23d850", @octoshift_migration_archive.storage_s3_bucket
      end
    end
  end

  context "#storage_s3_key" do
    test "returns expected S3 key" do
      expected_storage_s3_key = "organizations/#{@organization.id}/archives/#{@octoshift_migration_archive.guid}"
      policy = @octoshift_migration_archive.storage_policy

      assert_equal expected_storage_s3_key, @octoshift_migration_archive.storage_s3_key(policy)
    end
  end

  context ".create" do
    test "emits a Datadog gh.migration_tools.octoshift_migration_archive.create.increment metric" do
      create(:octoshift_migration_archive, organization: @organization, uploader: @user)

      ddog_metric = GitHub.dogstats.increments("gh.migration_tools.octoshift_migration_archive.create.increment").first

      assert_equal 1, ddog_metric.value
      assert_equal Set.new(["org_id:#{@organization.id}"]), ddog_metric.tags
    end

    test "emits a Datadog gh.migration_tools.octoshift_migration_archive.create.count metric" do
      create(:octoshift_migration_archive, organization: @organization, uploader: @user)

      ddog_metric = GitHub.dogstats.counts("gh.migration_tools.octoshift_migration_archive.create.count").first

      assert_equal 1234, ddog_metric.value
      assert_equal Set.new(["org_id:#{@organization.id}"]), ddog_metric.tags
    end

    test "does not emit a Datadog gh.migration_tools.octoshift_migration_archive.create.increment metric when updating an existing record" do
      octoshift_migration_archive = create(:octoshift_migration_archive, organization: @organization, uploader: @user)
      octoshift_migration_archive.save!

      assert_equal 1, GitHub.dogstats.increments("gh.migration_tools.octoshift_migration_archive.create.increment").count
    end

    test "does not emit a Datadog gh.migration_tools.octoshift_migration_archive.create.count metric when updating an existing record" do
      octoshift_migration_archive = create(:octoshift_migration_archive, organization: @organization, uploader: @user)
      octoshift_migration_archive.save!

      assert_equal 1, GitHub.dogstats.counts("gh.migration_tools.octoshift_migration_archive.create.count").count
    end
  end

  context ".destroy" do
    test "invokes the storage_delete method" do
      @octoshift_migration_archive.expects(:storage_delete_object).once
      @octoshift_migration_archive.destroy
    end

    test "emits a Datadog gh.migration_tools.octoshift_migration_archive.destroy.increment metric" do
      @octoshift_migration_archive.destroy

      ddog_metric = GitHub.dogstats.increments("gh.migration_tools.octoshift_migration_archive.destroy.increment").first

      assert_equal 1, ddog_metric.value
      assert_equal Set.new(["org_id:#{@organization.id}"]), ddog_metric.tags
    end

    test "emits a Datadog gh.migration_tools.octoshift_migration_archive.destroy.count metric" do
      @octoshift_migration_archive.destroy

      ddog_metric = GitHub.dogstats.counts("gh.migration_tools.octoshift_migration_archive.destroy.count").first

      assert_equal 1234, ddog_metric.value
      assert_equal Set.new(["org_id:#{@organization.id}"]), ddog_metric.tags
    end
  end
end
