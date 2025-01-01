# typed: false
# frozen_string_literal: true

require "test_helper"

class LogStorageHelperTest < GitHub::TestCase

  fixtures do
    @user = create(:user)
    @org = create(:organization)
    @org.add_member(@user, action: :admin)
    @log_name = Faker::Lorem.word
    @content = Faker::Lorem.paragraph
  end

  setup do
    @s3_client = Aws::S3::Client.new(stub_responses: true)
    Octoshift::Service::LogStorageHelper.any_instance.stubs(:memory_alpha_client).returns(@s3_client)
  end

  context "upload_repo_log" do
    test "uploads a repository log contents to memory alpha client" do
      @s3_client.expects(:put_object).with do |args|
        assert [::File, ::Tempfile].include?(args[:body].class)
        assert_equal GitHub.octoshift_memory_alpha_bucket, args[:bucket]
        assert_equal "#{@org.name}/#{@log_name}-logs.txt", args[:key]
      end

      Octoshift::Service::LogStorageHelper.new.upload_repo_log(
        @org.name,
        @log_name,
        @content
      )
    end

    test "raises an error if the Azure credentials are missing" do
      @s3_client.stubs(:put_object).raises(Aws::Sigv4::Errors::MissingCredentialsError.new("Missing credentials, provide credentials with one of the following options"))

      error = assert_raises(Octoshift::Service::LogStorageHelper::MissingCredentialsError) do
        Octoshift::Service::LogStorageHelper.new.upload_repo_log(@org.name, @log_name, @content)
      end

      assert_equal "Could not connect to Azure: Missing Credentials. Could not upload logs for: #{@log_name}", error.message
    end

    test "raises an error if the log could not be uploaded" do
      @s3_client.stubs(:put_object).raises(Aws::S3::Errors::ServiceError.new({}, "Requested key cannot be found"))

      error = assert_raises(Octoshift::Service::LogStorageHelper::UploadError) do
        Octoshift::Service::LogStorageHelper.new.upload_repo_log(@org.name, @log_name, @content)
      end

      assert_equal "Failed to upload migration log for: #{@log_name}", error.message
    end
  end

  context "get_repo_log_url" do
    test "returns a signed url for a repository log" do
      url_regex = %r{https://objects-staging-origin.githubusercontent.com/octoshiftmigrationlogs/#{@org.name}/#{@log_name}\.*}
      assert_match url_regex, Octoshift::Service::LogStorageHelper.new.get_repo_log_url(@org.name, @log_name)
    end

    test "raises an error if the download url could not be generated" do
      @s3_client.stubs(:get_object).raises(Aws::S3::Errors::NotFound.new({}, "Requested key cannot be found"))

      error = assert_raises(Octoshift::Service::LogStorageHelper::GenerateUrlError) do
        Octoshift::Service::LogStorageHelper.new.get_repo_log_url(@org.name, @log_name)
      end

      assert_equal "Failed to generate url to download migration log for: #{@log_name}", error.message
    end
  end
end
