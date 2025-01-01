# typed: true
# frozen_string_literal: true

require "test_helper"

class OctoshiftTwirpConnectionBuilderTest < GitHub::TestCase
  MOCK_URL = "https://octoshift.example.com/"
  MOCK_STAGING_URL = "https://octoshift-staging.example.com/"
  MOCK_LOAD_TESTING_URL = "https://octoshift-load-testing.example.com/"
  MOCK_REVIEW_LAB_URL = "https://octoshift-review-lab.example.com/"

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures

  fixtures do
    @organization = create(:organization)
    @enterprise = create(:business)
    @faraday = Octoshift::Twirp::ConnectionBuilder.new.build
  end

  setup do
    GitHub.context.push(request_id: "abc-123")
    GitHub.stubs(:octoshift_url).returns(MOCK_URL)
    GitHub.stubs(:octoshift_staging_url).returns(MOCK_STAGING_URL)
    GitHub.stubs(:octoshift_load_testing_url).returns(MOCK_LOAD_TESTING_URL)
    GitHub.stubs(:octoshift_review_lab_url).returns(MOCK_REVIEW_LAB_URL)
  end

  context "for staging" do
    context "#for_organization" do
      context "when octoshift_use_staging feature flag is enabled for an org" do
        test "uses the staging URL" do
          GitHub.flipper[:octoshift_use_staging].enable(@organization)
          faraday = Octoshift::Twirp::ConnectionBuilder.for_organization(@organization).build

          assert_equal MOCK_STAGING_URL, faraday.build_url.to_s
        end
      end

      context "when octoshift_use_staging feature flag is not enabled for an org" do
        test "uses the default URL" do
          GitHub.flipper[:octoshift_use_staging].disable(@organization)
          faraday = Octoshift::Twirp::ConnectionBuilder.for_organization(@organization).build

          assert_equal MOCK_URL, faraday.build_url.to_s
        end
      end
    end

    context "#for_enterprise" do
      context "when octoshift_use_staging feature flag is enabled for an enterprise" do
        test "uses the staging URL" do
          GitHub.flipper[:octoshift_use_staging].enable(@enterprise)
          faraday = Octoshift::Twirp::ConnectionBuilder.for_enterprise(@enterprise).build

          assert_equal MOCK_STAGING_URL, faraday.build_url.to_s
        end
      end

      context "when octoshift_use_staging feature flag is not enabled for an enterprise" do
        test "uses the default URL" do
          GitHub.flipper[:octoshift_use_staging].disable(@enterprise)
          faraday = Octoshift::Twirp::ConnectionBuilder.for_enterprise(@enterprise).build

          assert_equal MOCK_URL, faraday.build_url.to_s
        end
      end

      context "when enterprise is for regression tests", skip_enterprise: true do
        test "uses the review-lab URL for Teenyverse" do
          enterprise = create(:business, :enterprise_managed, name: "Teenyverse")
          faraday = Octoshift::Twirp::ConnectionBuilder.for_enterprise(enterprise).build

          assert_equal MOCK_REVIEW_LAB_URL, faraday.build_url.to_s
        end
      end
    end
  end

  context "for load testing" do
    context "#for_organization" do
      test "uses the load-testing URL for octoshift-load-testing org" do
        review_org = create(:organization, name: "octoshift-load-testing")
        faraday = Octoshift::Twirp::ConnectionBuilder.for_organization(review_org).build

        assert_equal MOCK_LOAD_TESTING_URL, faraday.build_url.to_s
      end

      test "does not use the load-testing URL for other orgs" do
        faraday = Octoshift::Twirp::ConnectionBuilder.for_organization(@organization).build

        refute_equal MOCK_LOAD_TESTING_URL, faraday.build_url.to_s
      end
    end
  end

  context "for review_lab" do
    context "#for_organization" do
      test "uses the review-lab URL for octoshift-review-lab org" do
        review_org = create(:organization, name: "octoshift-review-lab")
        faraday = Octoshift::Twirp::ConnectionBuilder.for_organization(review_org).build

        assert_equal MOCK_REVIEW_LAB_URL, faraday.build_url.to_s
      end

      test "does not use the review-lab URL for other orgs" do
        faraday = Octoshift::Twirp::ConnectionBuilder.for_organization(@organization).build

        refute_equal MOCK_REVIEW_LAB_URL, faraday.build_url.to_s
      end
    end

    context "#for_enterprise", skip_enterprise: true do
      test "uses the review-lab URL for Teenyverse enterprise" do
        review_lab_enterprise = create(:business, :enterprise_managed, name: "Teenyverse")
        faraday = Octoshift::Twirp::ConnectionBuilder.for_enterprise(review_lab_enterprise).build

        assert_equal MOCK_REVIEW_LAB_URL, faraday.build_url.to_s
      end

      test "uses the default URL for other enterprises" do
        GitHub.flipper[:octoshift_use_staging].disable(@enterprise)
        faraday = Octoshift::Twirp::ConnectionBuilder.for_enterprise(@enterprise).build

        assert_equal MOCK_URL, faraday.build_url.to_s
      end
    end
  end

  context ".staging" do
    test "uses the staging URL" do
      faraday = Octoshift::Twirp::ConnectionBuilder.staging.build

      assert_equal MOCK_STAGING_URL, faraday.build_url.to_s
    end
  end

  context ".review_lab" do
    test "uses the staging URL" do
      faraday = Octoshift::Twirp::ConnectionBuilder.review_lab.build

      assert_equal GitHub.octoshift_review_lab_url, faraday.build_url.to_s
    end
  end

  test "sets open timeout to 0.25" do
    assert_equal  0.25, @faraday.options.open_timeout
  end

  test "sets the User-Agent header" do
    assert_equal "github-#{GitHub.role}/#{GitHub.current_sha}", @faraday.get.env.request_headers["User-Agent"]
  end

  test "sets the X-GitHub-Request-Id header" do
    assert_equal "abc-123", @faraday.get.env.request_headers["X-GitHub-Request-Id"]
  end

  test "includes GitHub::FaradayMiddleware::RequestID middleware" do
    assert_includes @faraday.builder.handlers, GitHub::FaradayMiddleware::RequestID
  end

  # There doesn't seem to be a great way to actually test the middleware without digging into private APIs.
  # Just asserting the middleware is there and registered.
  test "includes Faraday::Request::Retry middleware" do
    assert_includes @faraday.builder.handlers, Faraday::Request::Retry
  end
end
