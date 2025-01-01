# typed: true
# frozen_string_literal: true

require "test_helper"

unless GitHub.single_business_environment?
  class EnterpriseInstallationUserAccountsUploadTest < GitHub::TestCase
    include UploadableTestHelpers

    fixtures do
      @admin = create :user
      @business = create :business, owners: [@admin]
      @installation = create :enterprise_installation, owner: @business
      @upload = EnterpriseInstallationUserAccountsUpload.new business: @business
      save_file_for_uploadable @upload,
        name: "github-localhost-20190319115623.json",
        size: 1.megabyte,
        content_type: "application/json"
    end

    context "validations" do
      test "includes json content type" do
        content_types = EnterpriseInstallationUserAccountsUpload.allowed_content_types
        assert_includes content_types, "application/json"
      end

      test "requires business" do
        upload = build :enterprise_installation_user_accounts_upload, business: nil
        refute_predicate upload, :valid?
        assert_predicate upload.errors[:business], :present?
      end

      test "requires content_type" do
        upload = build :enterprise_installation_user_accounts_upload, content_type: nil
        refute_predicate upload, :valid?
        assert_predicate upload.errors[:content_type], :present?
      end

      test "requires content_type to be application/json" do
        upload = build :enterprise_installation_user_accounts_upload, content_type: "image/jpeg"
        refute_predicate upload, :valid?
        assert_predicate upload.errors[:content_type], :present?
      end

      test "requires name" do
        upload = build :enterprise_installation_user_accounts_upload, name: nil
        refute_predicate upload, :valid?
        assert_predicate upload.errors[:name], :present?
      end

      test "enterprise_installation must be owned by business if provided" do
        org_installation = create :enterprise_installation, owner: create(:organization)
        upload = build :enterprise_installation_user_accounts_upload, \
          business: @business, enterprise_installation: org_installation
        refute_predicate upload, :valid?
        assert_predicate upload.errors[:enterprise_installation], :present?
      end

      test "enterprise_installation can be set when valid" do
        @upload.update enterprise_installation: @installation
        assert_predicate @upload, :valid?
      end

      test "requires size within 1..25.megabytes" do
        upload = build :enterprise_installation_user_accounts_upload, size: 0
        refute_predicate upload, :valid?
        assert_predicate upload.errors[:size], :present?

        upload = build :enterprise_installation_user_accounts_upload, size: 100.megabytes
        refute_predicate upload, :valid?
        assert_predicate upload.errors[:size], :present?
      end
    end

    context "initialisation" do
      test "gets content type from upload" do
        assert_equal "application/json", @upload.content_type
      end

      test "gets size from upload" do
        assert_equal 1.megabyte, @upload.size
      end

      test "gets filename from upload" do
        assert_equal "github-localhost-20190319115623.json", @upload.name
      end

      test "sets guid" do
        assert_equal @upload, EnterpriseInstallationUserAccountsUpload.find_by(guid: @upload.guid)
      end

      test "starts in the starter state" do
        assert EnterpriseInstallationUserAccountsUpload.new.starter?
      end

      test "sets state on upload" do
        assert @upload.uploaded?
      end
    end

    context "associations" do
      test "business can be successfully destroyed when upload linked to business and installation" do
        @upload.update enterprise_installation: @installation
        assert_same_elements [@upload], @business.enterprise_installation_user_accounts_uploads.to_a
        assert_same_elements [@upload], @installation.user_accounts_uploads.to_a

        @business.destroy

        assert_equal 0, EnterpriseInstallationUserAccountsUpload.count
        assert_equal 0, EnterpriseInstallation.count
        assert_equal 0, Business.count
      end
    end

    context "#storage_provider" do
      test "uses S3 production data when feature flag is enabled" do
        GitHub.s3_uploads_enabled = true
        GitHub.flipper[:enterprise_license_s3_production_data].enable

        new_upload = EnterpriseInstallationUserAccountsUpload.new business: @business
        save_file_for_uploadable new_upload,
          name: "github-localhost-20190319115623.json",
          size: 1.megabyte,
          content_type: "application/json"

        assert_equal new_upload.storage_provider, :s3_production_data
      end

      test "storage provider being changed only affects new uploads" do
        GitHub.s3_uploads_enabled = true

        GitHub.flipper[:enterprise_license_s3_production_data].disable
        old_upload = EnterpriseInstallationUserAccountsUpload.new business: @business
        save_file_for_uploadable old_upload,
          name: "github-localhost-20190319115623.json",
          size: 1.megabyte,
          content_type: "application/json"

        GitHub.flipper[:enterprise_license_s3_production_data].enable

        new_upload = EnterpriseInstallationUserAccountsUpload.new business: @business
        save_file_for_uploadable new_upload,
          name: "github-localhost-20190319115623.json",
          size: 1.megabyte,
          content_type: "application/json"

        assert_equal old_upload.storage_provider, :default
        assert_equal new_upload.storage_provider, :s3_production_data
      end
    end

    context "#download_url" do
      test "gets S3 production data download URL" do
        GitHub.s3_uploads_enabled = true
        @upload.storage_provider = :s3_production_data
        @upload.save!

        download_uri = URI(@upload.download_url(actor: @admin))

        assert_equal "#{EnterpriseInstallationUserAccountsUpload.storage_s3_new_bucket}.s3.amazonaws.com", download_uri.host
        assert_equal "/#{@business.slug}/#{@upload.guid}", download_uri.path
        escaped_eq = "%3D"
        assert_match %r{response-content-disposition=filename#{escaped_eq}#{@upload.name}}x, download_uri.query
      end

      test "gets S3 legacy download URL" do
        GitHub.s3_uploads_enabled = true
        @upload.storage_provider = :default
        @upload.save!

        download_uri = URI(@upload.download_url(actor: @admin))

        assert_equal "#{EnterpriseInstallationUserAccountsUpload.storage_s3_bucket}.s3.amazonaws.com", download_uri.host
        assert_equal "/businesses/#{@business.slug}/#{@upload.guid}", download_uri.path
        escaped_eq = "%3D"
        assert_match %r{response-content-disposition=filename#{escaped_eq}#{@upload.name}}x, download_uri.query
      end
    end
  end
end
