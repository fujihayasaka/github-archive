# typed: true
# frozen_string_literal: true

require "test_helper"

class MigrationFileTest < GitHub::TestCase
  include UploadableTestHelpers

  setup do
    GitHub.flipper[:gh_migrator_increased_export_size].disable
  end

  fixtures do
    @org = create(:organization)
    @user = create(:user)
    @current_user = create(:user)
    @repository1 = create :repository, owner: @org
    @repository2 = create :repository, owner: @org
    @migration = create(:migration, owner: @org, creator: @owner, state: :ready)
    @migration_file = create(:migration_file, migration: @migration)
    @valid_non_multipart_size          = 5.gigabytes
    @invalid_non_multipart_size        = 5.gigabytes + 1
    @non_multipart_size_range          = 1..5.gigabytes
    @valid_multipart_size              = 30.gigabytes
    @invalid_multipart_size            = 30.gigabytes + 1
    @multipart_size_range              = 1..30.gigabytes
    @valid_increased_multipart_size    = 40.gigabytes
    @invalid_increased_multipart_size  = 40.gigabytes + 1
    @valid_ghes_multipart_size         = 90.gigabytes
    @invalid_ghes_multipart_size       = 90.gigabytes + 1
    @valid_local_migration_file_size   = 50.gigabytes
    @invalid_local_migration_file_size = 50.gigabytes + 1
  end

  setup do
    @helper = FakeHelper.new
    GitHub.migrations_blob_storage_type = ""
    GitHub.migrations_aws_access_key = ""
    GitHub.migrations_aws_service_url = ""
    GitHub.migrations_aws_secret_key = ""
  end

  context "download_url" do
    test "gets s3 prod data download URL" do
      GitHub.s3_uploads_enabled = true

      @migration = create :migration, owner: @org, creator: @user
      @migration.repositories = [@repository1, @repository2]
      file = @migration.build_file
      file.storage_provider = :s3_production_data
      file.name = "export.tar.gz"
      file.size = 1
      file.uploader = @user
      file.content_type = "application/gzip"
      file.save!

      download_uri = URI(file.download_url(actor: @user))

      assert_equal "#{MigrationFile.storage_s3_new_bucket}.s3.amazonaws.com", download_uri.host
      assert_equal "/#{@migration.id}/#{file.id}", download_uri.path

      escaped_eq = "%3D"
      assert_match %r{response-content-disposition=filename#{escaped_eq}#{@migration.guid}.tar.gz}x, download_uri.query
    end

    test "gets s3 legacy download URL" do
      GitHub.s3_uploads_enabled = true

      @migration = create :migration, owner: @org, creator: @user
      @migration.repositories = [@repository1, @repository2]
      file = @migration.build_file
      file.storage_provider = :default
      file.name = "export.tar.gz"
      file.size = 1
      file.uploader = @user
      file.content_type = "application/gzip"
      file.save!

      download_uri = URI(file.download_url(actor: @user))

      assert_equal "#{MigrationFile.storage_s3_bucket}.s3.amazonaws.com", download_uri.host
      assert_match %r{
          \A
          /migration                              # the fixed prefix
          /\d+/\d+                                # the migration id and file id
          \z
        }x, download_uri.path

      escaped_eq = "%3D"
      assert_match %r{response-content-disposition=filename#{escaped_eq}#{@migration.guid}.tar.gz}x, download_uri.query
    end

    if GitHub.enterprise?
      test "gets bring your own s3 download URL" do
        GitHub.migrations_blob_storage_type = "s3"
        GitHub.migrations_s3_bucket = "test"
        GitHub.migrations_aws_access_key = "access"
        GitHub.migrations_aws_service_url = "https://s3.us-east-1.amazonaws.com"
        GitHub.migrations_aws_secret_key = "secret"

        @migration = create :migration, owner: @org, creator: @user
        @migration.repositories = [@repository1, @repository2]
        file = @migration.build_file
        file.storage_provider = :s3_production_data
        file.name = "export.tar.gz"
        file.size = 1
        file.uploader = @user
        file.content_type = "application/gzip"
        file.save!

        download_uri = URI(file.download_url(actor: @user))

        assert_equal "#{file.storage_s3_bucket}.s3.amazonaws.com", download_uri.host
        assert_equal "/#{file.name}", download_uri.path

        escaped_eq = "%3D"
        assert_match %r{response-content-disposition=filename#{escaped_eq}#{@migration.guid}.tar.gz}x, download_uri.query
      end

      test "gets local download url" do
        GitHub.storage_cluster_enabled = true

        @migration = create :migration, owner: @org, creator: @user
        @migration.repositories = [@repository1, @repository2]
        file = @migration.build_file
        file.uploader = @user
        file.size = 10
        save_file_for_uploadable file, name: "export.tar.gz"

        download_uri = URI(file.download_url(actor: @user))
        assert_match %r{\Ahttp:\/\/alambic\.github\.test\/storage\/migrations\/\d+\/archive\/[0-9a-f\-]+\?token=.+}, download_uri.to_s
      end
    end
  end

  context "download (counter)" do
    test "instruments the download" do
      GitHub.s3_uploads_enabled = false
      GitHub.storage_cluster_enabled = true

      @migration = create :migration, owner: @org, creator: @user
      @migration.repositories = [@repository1, @repository2]
      file = @migration.build_file
      file.uploader = @user
      save_file_for_uploadable file, name: "export.tar.gz"

      events = subscribe "migration.download"
      expected_payload = {
        migration_id: @migration.id,
        org: @org.to_s,
        org_id: @org.id,
        repo: [@repository1.name_with_owner, @repository2.name_with_owner],
        repo_id: [@repository1.id, @repository2.id],
        public_repo: true,
        started_by: @user.to_s,
        started_by_id: @user.id,
      }

      file.download

      assert event = events.pop, "an event was expected"
      assert_equal "migration.download", event.name
      assert_equal expected_payload, event.payload
    end
  end

  context "multipart uploads" do
    test "the :migration_file factory is valid" do
      assert_valid @migration_file
    end

    test "it validates non-multipart file size is less than or equal to 5GB" do
      @migration_file.size = @valid_non_multipart_size

      assert_valid @migration_file
    end

    test "it fails validation on non-multipart file size larger than 5GB" do
      @migration_file.size = @invalid_non_multipart_size

      refute_valid @migration_file
      assert_equal "must be less than 5 GB and greater than zero bytes", @migration_file.errors[:size].first
    end

    test "it validates multipart file size is less than or equal to 30GB" do
      @migration_file.supports_multi_part_upload = true
      @migration_file.size = @valid_multipart_size

      assert_valid @migration_file
    end

    test "it fails validation on multipart file size larger than 30GB" do
      GitHub.stubs(:enterprise?).returns(false) # rubocop:todo GitHub/DontStubEnterpriseInTests

      @migration_file.supports_multi_part_upload = true
      @migration_file.size = @invalid_multipart_size

      refute_valid @migration_file
      assert_equal "must be less than 30 GB and greater than zero bytes", @migration_file.errors[:size].first
    end

    context "with the gh_migrator_increased_export_size feature flag enabled for an org" do
      test "it validates multipart file size is less than or equal to 40GB" do
        GitHub.flipper[:gh_migrator_increased_export_size].enable(@org)

        @migration_file.supports_multi_part_upload = true
        @migration_file.size = @valid_increased_multipart_size

        assert_valid @migration_file
      end

      test "it fails validation on multipart file size larger than 40GB" do
        GitHub.stubs(:enterprise?).returns(false) # rubocop:todo GitHub/DontStubEnterpriseInTests
        GitHub.flipper[:gh_migrator_increased_export_size].enable(@org)

        @migration_file.supports_multi_part_upload = true
        @migration_file.size = @invalid_increased_multipart_size

        refute_valid @migration_file
        assert_equal "must be less than 40 GB and greater than zero bytes", @migration_file.errors[:size].first
      end
    end
  end

  if GitHub.enterprise?
    context "multipart uploads" do
      context "export migrations azure" do
        test "returns exports azure storage policy" do
          GitHub.migrations_blob_storage_type = "azure"
          GitHub.migrations_azure_connection_string = "connection_string"

          assert @migration_file.use_azure_storage?
          assert_kind_of Storage::AzurePolicy, @migration_file.storage_policy
        end

        test "returns exports azure storage client" do
          GitHub.migrations_blob_storage_type = "azure"
          GitHub.migrations_azure_connection_string = "connection_string"

          assert_kind_of GitHub::AzureSnapshotUploader, @migration_file.storage_client
        end
      end

      context "export migrations s3" do
        test "returns exports s3 policy" do
          GitHub.migrations_blob_storage_type = "s3"
          GitHub.migrations_aws_access_key = "access"
          GitHub.migrations_aws_service_url = "https://s3.us-east-1.amazonaws.com"
          GitHub.migrations_aws_secret_key = "secret"

          assert @migration_file.use_s3_storage?
          assert_kind_of Storage::S3Policy, @migration_file.storage_policy
        end

        test "returns exports s3 client" do
          GitHub.migrations_blob_storage_type = "s3"
          GitHub.migrations_aws_access_key = "access"
          GitHub.migrations_aws_service_url = "https://s3.us-east-1.amazonaws.com"
          GitHub.migrations_aws_secret_key = "secret"

          assert_kind_of Aws::S3::Client, @migration_file.storage_client
        end

        test "has the proper number of slashes" do
          GitHub.migrations_blob_storage_type = "s3"
          GitHub.migrations_aws_access_key = "access"
          GitHub.migrations_aws_service_url = "https://s3.us-east-1.amazonaws.com"
          GitHub.migrations_aws_secret_key = "secret"

          s3_key = @migration_file.repository_migrations_s3_fields[:s3_key]

          assert_equal s3_key, "#{@migration_file.name}"
        end
      end

      test "it validates multipart file size is less than or equal to 90GB" do
        @migration_file.supports_multi_part_upload = true
        @migration_file.size = @valid_ghes_multipart_size

        assert_valid @migration_file
      end

      test "it fails validation on multipart file size larger than 90GB" do
        @migration_file.supports_multi_part_upload = true
        @migration_file.size = @invalid_ghes_multipart_size

        refute_valid @migration_file
        assert_equal "must be less than 90 GB and greater than zero bytes", @migration_file.errors[:size].first
      end
    end

    context "export migrations local" do
      test "returns exports cluster policy" do
        GitHub.storage_cluster_enabled = true

        assert_kind_of Storage::ClusterPolicy, @migration_file.storage_policy
        refute @migration_file.use_s3_storage?
        refute @migration_file.use_azure_storage?
      end

      test "it validates migration file size is less than or equal to 50GB" do
        GitHub.storage_cluster_enabled = true

        @migration_file.size = @valid_local_migration_file_size

        assert_valid @migration_file
      end

      test "it fails validation on file size larger than 50GB" do
        GitHub.storage_cluster_enabled = true

        @migration_file.size = @invalid_local_migration_file_size

        refute_valid @migration_file
        assert_equal "must be less than 50 GB and greater than zero bytes", @migration_file.errors[:size].first
      end
    end
  end
end
