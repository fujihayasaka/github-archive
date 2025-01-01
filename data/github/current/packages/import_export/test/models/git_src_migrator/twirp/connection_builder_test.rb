# typed: true
# frozen_string_literal: true

require "test_helper"

module GitSrcMigrator
  module Twirp
    class ConnectionBuilderTest < GitHub::TestCase
      setup do
        GitHub.stubs(:git_src_migrator_url).returns("http://gsm.localhost:4567/twirp")
        GitHub.stubs(:git_src_migrator_hmac_key).returns("example_hmac_key")

        GitHub.stubs(:git_src_migrator_staging_url).returns("http://gsm-staging.localhost:4567/twirp")
        GitHub.stubs(:git_src_migrator_staging_hmac_key).returns("example_staging_hmac_key")

        GitHub.stubs(:git_src_migrator_review_lab_url).returns("http://gsm-review-lab.localhost:4567/twirp")
        GitHub.stubs(:git_src_migrator_review_lab_hmac_key).returns("example_review_lab_hmac_key")

        GitHub.stubs(:role).returns("example_role")
        GitHub.stubs(:current_sha).returns("example_current_sha")
        GitHub.context.push(request_id: "example_github_context")

        @connection_builder = GitSrcMigrator::Twirp::ConnectionBuilder.new
        @faraday_client = @connection_builder.build

        @user = create(:user)
        @organization = create(:organization)

        disable_feature_flag(:import_export_gitops_on_actions_use_staging, @organization)
        disable_feature_flag(:import_export_gitops_on_actions_use_review_lab, @organization)
      end

      context ".new" do
        test "sets the url_prefix to \"http://gsm.localhost:4567/twirp\"" do
          assert_equal URI("http://gsm.localhost:4567/twirp"), @faraday_client.url_prefix
        end

        test "sets the HMAC key to \"example_hmac_key\"" do
          assert_equal "example_hmac_key", @connection_builder.hmac_key
        end

        context "with a url of \"http://gsm.localhost:4567/example\"" do
          test "sets the url_prefix to \"http://gsm.localhost:4567/example\"" do
            faraday_client = GitSrcMigrator::Twirp::ConnectionBuilder.new(url: "http://gsm.localhost:4567/example").build

            assert_equal URI("http://gsm.localhost:4567/example"), faraday_client.url_prefix
          end
        end

        context "with a hmac_key of \"other_hmac_key\"" do
          test "sets the HMAC key to \"other_hmac_key\"" do
            connection_builder = GitSrcMigrator::Twirp::ConnectionBuilder.new(hmac_key: "other_hmac_key")

            assert_equal "other_hmac_key", connection_builder.hmac_key
          end
        end
      end

      context ".for_owner" do
        context "with an organization owner" do
          context "with the import_export_gitops_on_actions_use_staging feature flag disabled" do

            test "sets the url_prefix to \"http://gsm.localhost:4567/twirp\"" do
              disable_feature_flag(:import_export_gitops_on_actions_use_staging, @organization)
              connection_builder = GitSrcMigrator::Twirp::ConnectionBuilder.for_owner(@organization)

              assert_equal URI("http://gsm.localhost:4567/twirp"), connection_builder.build.url_prefix
            end

            test "sets the HMAC key to \"example_hmac_key\"" do
              disable_feature_flag(:import_export_gitops_on_actions_use_staging, @organization)
              connection_builder = GitSrcMigrator::Twirp::ConnectionBuilder.for_owner(@organization)

              assert_equal "example_hmac_key", connection_builder.hmac_key
            end
          end

          context "with the import_export_gitops_on_actions_use_staging feature flag enabled" do
            test "sets the url_prefix to \"http://gsm-staging.localhost:4567/twirp\"" do
              enable_feature_flag(:import_export_gitops_on_actions_use_staging, @organization)
              connection_builder = GitSrcMigrator::Twirp::ConnectionBuilder.for_owner(@organization)

              assert_equal URI("http://gsm-staging.localhost:4567/twirp"), connection_builder.build.url_prefix
            end

            test "sets the HMAC key to \"example_staging_hmac_key\"" do
              enable_feature_flag(:import_export_gitops_on_actions_use_staging, @organization)
              connection_builder = GitSrcMigrator::Twirp::ConnectionBuilder.for_owner(@organization)

              assert_equal "example_staging_hmac_key", connection_builder.hmac_key
            end
          end

          context "with the import_export_gitops_on_actions_use_review_lab feature flag disabled" do
            test "sets the url_prefix to \"http://gsm.localhost:4567/twirp\"" do
              disable_feature_flag(:import_export_gitops_on_actions_use_review_lab, @organization)
              connection_builder = GitSrcMigrator::Twirp::ConnectionBuilder.for_owner(@organization)

              assert_equal URI("http://gsm.localhost:4567/twirp"), connection_builder.build.url_prefix
            end

            test "sets the HMAC key to \"example_hmac_key\"" do
              disable_feature_flag(:import_export_gitops_on_actions_use_review_lab, @organization)
              connection_builder = GitSrcMigrator::Twirp::ConnectionBuilder.for_owner(@organization)

              assert_equal "example_hmac_key", connection_builder.hmac_key
            end
          end

          context "with the import_export_gitops_on_actions_use_review_lab feature flag enabled" do
            test "sets the url_prefix to \"http://gsm-review-lab.localhost:4567/twirp\"" do
              enable_feature_flag(:import_export_gitops_on_actions_use_review_lab, @organization)
              connection_builder = GitSrcMigrator::Twirp::ConnectionBuilder.for_owner(@organization)

              assert_equal URI("http://gsm-review-lab.localhost:4567/twirp"), connection_builder.build.url_prefix
            end

            test "sets the HMAC key to \"example_review_lab_hmac_key\"" do
              enable_feature_flag(:import_export_gitops_on_actions_use_review_lab, @organization)
              connection_builder = GitSrcMigrator::Twirp::ConnectionBuilder.for_owner(@organization)

              assert_equal "example_review_lab_hmac_key", connection_builder.hmac_key
            end
          end

          context "with the import_export_gitops_on_actions_use_staging and import_export_gitops_on_actions_use_review_lab feature flags enabled" do
            test "sets the url_prefix to \"http://gsm-staging.localhost:4567/twirp\"" do
              enable_feature_flag(:import_export_gitops_on_actions_use_staging, @organization)
              enable_feature_flag(:import_export_gitops_on_actions_use_review_lab, @organization)
              connection_builder = GitSrcMigrator::Twirp::ConnectionBuilder.for_owner(@organization)

              assert_equal URI("http://gsm-staging.localhost:4567/twirp"), connection_builder.build.url_prefix
            end

            test "sets the HMAC key to \"example_staging_hmac_key\"" do
              enable_feature_flag(:import_export_gitops_on_actions_use_staging, @organization)
              enable_feature_flag(:import_export_gitops_on_actions_use_review_lab, @organization)
              connection_builder = GitSrcMigrator::Twirp::ConnectionBuilder.for_owner(@organization)

              assert_equal "example_staging_hmac_key", connection_builder.hmac_key
            end
          end
        end

        context "with a user owner" do
          context "with the import_export_gitops_on_actions_use_staging feature flag disabled" do
            test "sets the url_prefix to \"http://gsm.localhost:4567/twirp\"" do
              disable_feature_flag(:import_export_gitops_on_actions_use_staging, @user)
              connection_builder = GitSrcMigrator::Twirp::ConnectionBuilder.for_owner(@user)

              assert_equal URI("http://gsm.localhost:4567/twirp"), connection_builder.build.url_prefix
            end

            test "sets the HMAC key to \"example_hmac_key\"" do
              disable_feature_flag(:import_export_gitops_on_actions_use_staging, @user)
              connection_builder = GitSrcMigrator::Twirp::ConnectionBuilder.for_owner(@user)

              assert_equal "example_hmac_key", connection_builder.hmac_key
            end
          end

          context "with the import_export_gitops_on_actions_use_staging feature flag enabled" do
            test "sets the url_prefix to \"http://gsm-staging.localhost:4567/twirp\"" do
              enable_feature_flag(:import_export_gitops_on_actions_use_staging, @user)
              connection_builder = GitSrcMigrator::Twirp::ConnectionBuilder.for_owner(@user)

              assert_equal URI("http://gsm-staging.localhost:4567/twirp"), connection_builder.build.url_prefix
            end

            test "sets the HMAC key to \"example_staging_hmac_key\"" do
              enable_feature_flag(:import_export_gitops_on_actions_use_staging, @user)
              connection_builder = GitSrcMigrator::Twirp::ConnectionBuilder.for_owner(@user)

              assert_equal "example_staging_hmac_key", connection_builder.hmac_key
            end
          end

          context "with the import_export_gitops_on_actions_use_review_lab feature flag disabled" do
            test "sets the url_prefix to \"http://gsm.localhost:4567/twirp\"" do
              disable_feature_flag(:import_export_gitops_on_actions_use_review_lab, @user)
              connection_builder = GitSrcMigrator::Twirp::ConnectionBuilder.for_owner(@user)

              assert_equal URI("http://gsm.localhost:4567/twirp"), connection_builder.build.url_prefix
            end

            test "sets the HMAC key to \"example_hmac_key\"" do
              disable_feature_flag(:import_export_gitops_on_actions_use_review_lab, @user)
              connection_builder = GitSrcMigrator::Twirp::ConnectionBuilder.for_owner(@user)

              assert_equal "example_hmac_key", connection_builder.hmac_key
            end
          end

          context "with the import_export_gitops_on_actions_use_review_lab feature flag enabled" do
            test "sets the url_prefix to \"http://gsm-review-lab.localhost:4567/twirp\"" do
              enable_feature_flag(:import_export_gitops_on_actions_use_review_lab, @user)
              connection_builder = GitSrcMigrator::Twirp::ConnectionBuilder.for_owner(@user)

              assert_equal URI("http://gsm-review-lab.localhost:4567/twirp"), connection_builder.build.url_prefix
            end

            test "sets the HMAC key to \"example_review_lab_hmac_key\"" do
              enable_feature_flag(:import_export_gitops_on_actions_use_review_lab, @user)
              connection_builder = GitSrcMigrator::Twirp::ConnectionBuilder.for_owner(@user)

              assert_equal "example_review_lab_hmac_key", connection_builder.hmac_key
            end
          end

          context "with the import_export_gitops_on_actions_use_staging and import_export_gitops_on_actions_use_review_lab feature flags enabled" do
            test "sets the url_prefix to \"http://gsm-staging.localhost:4567/twirp\"" do
              enable_feature_flag(:import_export_gitops_on_actions_use_staging, @user)
              enable_feature_flag(:import_export_gitops_on_actions_use_review_lab, @user)
              connection_builder = GitSrcMigrator::Twirp::ConnectionBuilder.for_owner(@user)

              assert_equal URI("http://gsm-staging.localhost:4567/twirp"), connection_builder.build.url_prefix
            end

            test "sets the HMAC key to \"example_staging_hmac_key\"" do
              enable_feature_flag(:import_export_gitops_on_actions_use_staging, @user)
              enable_feature_flag(:import_export_gitops_on_actions_use_review_lab, @user)
              connection_builder = GitSrcMigrator::Twirp::ConnectionBuilder.for_owner(@user)

              assert_equal "example_staging_hmac_key", connection_builder.hmac_key
            end
          end
        end
      end

      context ".staging" do
        test "sets the url_prefix to \"http://gsm-staging.localhost:4567/twirp\"" do
          assert_equal URI("http://gsm-staging.localhost:4567/twirp"), GitSrcMigrator::Twirp::ConnectionBuilder.staging.build.url_prefix
        end

        test "sets the HMAC key to \"example_staging_hmac_key\"" do
          assert_equal "example_staging_hmac_key", GitSrcMigrator::Twirp::ConnectionBuilder.staging.hmac_key
        end
      end

      context "#build" do
        test "returns a GitHub::FaradayClient::Internal instance" do
          assert_instance_of GitHub::FaradayClient::Internal, @faraday_client
        end

        test "sets the url_prefix from GitHub.git_src_migrator_url" do
          assert_equal URI("http://gsm.localhost:4567/twirp"), @faraday_client.url_prefix
        end

        test "sets the open timeout to 0.25" do
          assert_equal 0.25, @faraday_client.options.open_timeout
        end

        test "sets the User-Agent header" do
          assert_equal "github-example_role/example_current_sha", @faraday_client.get.env.request_headers["User-Agent"]
        end

        test "sets the X-GitHub-Request-Id header" do
          assert_equal "example_github_context", @faraday_client.get.env.request_headers["X-GitHub-Request-Id"]
        end

        test "includes GitHub::FaradayMiddleware::RequestID middleware" do
          assert_includes @faraday_client.builder.handlers, GitHub::FaradayMiddleware::RequestID
        end

        # There doesn't seem to be a great way to actually test the middleware without digging into private APIs.
        # Just asserting the middleware is there and registered.
        test "includes Faraday::Request::Retry middleware" do
          assert_includes @faraday_client.builder.handlers, Faraday::Request::Retry
        end
      end
    end
  end
end
