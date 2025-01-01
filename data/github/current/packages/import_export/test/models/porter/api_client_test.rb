# typed: true
# frozen_string_literal: true

require "test_helper"

class PorterApiClientTest < GitHub::TestCase
  fixtures do
    @user = create :user, login: "spraints"
    @repo = create :repository, name: "greenhouse", owner: @user
    @porter = create :oauth_application
    GitHub.porter_app_id = @porter.id
  end

  setup do
    GitHub.porter_url_template = "http://import.github.dev/{owner}/{repository}/import"

    @client = Porter::ApiClient.new(
      current_user: @user,
      current_repository: @repo,
      auth_token: "APITOKEN",
    )

    insert_porter_api_cassette method_name.sub(/_L\d+$/, "")
  end

  teardown do
    nil while VCR.eject_cassette
  end

  context "start_import" do
    test "import starts ok" do
      result = @client.start_import "vcs" => "subversion", "vcs_url" => "http://aviary.com/roost"

      assert_equal({
        "vcs" => "subversion",
        "vcs_url" => "https://aviary.com/roost",
        "status" => "importing",
        "percent" => nil,
        "commit_count" => nil,
      }, result)
    end

    test "import does not restart" do
      assert_raises Porter::ApiClient::Error do
        @client.start_import "vcs" => "subversion", "vcs_url" => "http://aviary.com/roost"
      end
    end

    test "porter raises an error" do
      assert_raises Porter::ApiClient::Error do
        @client.start_import "vcs" => "subversion", "vcs_url" => "http://aviary.com/roost"
      end
    end
  end

  context "stop_import" do
    test "import stops ok" do
      @client.stop_import
    end

    test "import is not found" do
      assert_raises Porter::ApiClient::Error do
        @client.stop_import
      end
    end
  end

  context "import_status" do
    test "import status can be queried" do
      result = @client.import_status

      assert_equal({
        "vcs" => "subversion",
        "vcs_url" => "https://aviary.com/roost",
        "status" => "importing",
        "percent" => 8,
        "commit_count" => 3456,
        "has_large_files" => false,
        "large_files_size" => 0,
      }, result)
    end

    test "import status is not found" do
      assert_raises Porter::ApiClient::Error do
        @client.import_status
      end
    end
  end

  context "authors" do
    test "authors are present" do
      result = @client.authors({})

      assert_equal([
        {
          "id" => 123,
          "remote_id" => "someone@1234-567-8910",
          "remote_name" => "someone",
          "email" => "someone@1234-567-8910",
          "name" => "someone",
        },
      ], result)
    end

    test "no new authors" do
      result = @client.authors(since: 123)

      assert_equal [], result
    end

    test "import is not found" do
      assert_raises Porter::ApiClient::Error do
        @client.authors({})
      end
    end
  end

  context "update_author" do
    test "author is present" do
      response = @client.update_author(123, email: "spraints@gmail.com", name: "Matt Burke")

      assert_equal({
        "id" => 123,
        "remote_id" => "someone@1234-567-8910",
        "remote_name" => "someone",
        "email" => "spraints@gmail.com",
        "name" => "Matt Burke",
      }, response)
    end

    test "author is not found" do
      assert_raises Porter::ApiClient::Error do
        @client.update_author(124, email: "spraints@gmail.com", name: "Matt Burke")
      end
    end

    test "crappy data" do
      assert_raises Porter::ApiClient::Error do
        @client.update_author(123, remote_id: "can't touch this")
      end
    end
  end

  context "update_import" do
    test "with auth" do
      response = @client.update_import "vcs_username" => "username", "vcs_password" => "password"

      assert_equal({
        "vcs_url" => "https://aviary.com/roost",
        "status" => "detecting",
      }, response)
    end

    test "with tfvc project" do
      response = @client.update_import "vcs" => "tfvc", "tfvc_project" => "project1"
      assert_equal({
        "tfvc_project" => "project1",
        "vcs_url" => "https://aviary.com/roost",
        "status" => "importing",
        "percent" => nil,
        "commit_count" => nil,
        }, response)
    end

    test "with vcs type" do
      response = @client.update_import "vcs" => "git"
      assert_equal({
        "vcs" => "git",
        "vcs_url" => "https://aviary.com/roost",
        "status" => "importing",
        "percent" => nil,
        "commit_count" => nil,
        }, response)
    end

    test "import restarts ok" do
      response = @client.update_import

      assert_equal({
        "vcs" => "subversion",
        "vcs_url" => "https://aviary.com/roost",
        "status" => "importing",
        "percent" => nil,
        "commit_count" => nil,
      }, response)
    end

    test "restart with auth" do
      response = @client.update_import "vcs_username" => "username", "vcs_password" => "password"

      assert_equal({
        "vcs" => "subversion",
        "vcs_url" => "https://aviary.com/roost",
        "status" => "importing",
        "percent" => nil,
        "commit_count" => nil,
      }, response)
    end
  end

  context "large_files" do
    test "large files are present" do
      result = @client.large_files({ page: 1, per_page: 30 })

      assert_equal(
        {
          "total_count" => 1,
          "total_size" => 2700000,
          "entries" => [
            {
              "ref_name" => "refs/heads/master",
              "path" => "bigfile.bin",
              "oid" => "1b946fc71113a13f37a768c805a4bce453004e2327faf8f59c88085452c88c6a",
              "size" => 2700000,
            },
          ] }, result)
    end
  end

  context "response" do
    test "is available for success" do
      insert_porter_api_cassette "test_start_import_import_starts_ok"

      @client.start_import "vcs" => "subversion", "vcs_url" => "http://aviary.com/roost"

      assert_kind_of Faraday::Response, @client.last_response
    end
  end

  context "rate limiting" do
    test "requests hitting rate limit raise error" do
      Porter::ApiClient::Limiter.any_instance.expects(:rate_limit_increment).returns(stub(at_limit?: true))

      assert_raises Porter::ApiClient::ClientRequestLimit::Error do
        @client.large_files({ page: 1, per_page: 30 })
      end
    end
  end

  context "#token_for_current_user" do
    test "creates a token using Porter OAuth app" do
      token = @client.send(:token_for_current_user)
      refute_nil token

      access = OauthAccess.with_active_token(token)
      assert_equal access.application, @porter
      assert_equal @user, access.user
    end
  end

  def insert_porter_api_cassette(name)
    VCR.insert_cassette "porter/api_client_test/#{name}", record: :none
  end
end
