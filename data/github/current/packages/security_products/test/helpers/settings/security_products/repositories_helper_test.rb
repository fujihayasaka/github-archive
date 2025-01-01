# typed: true
# frozen_string_literal: true

require "test_helper"

class Settings::SecurityProducts::RepositoriesHelperTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper
  include SecurityProductsEnablementHelpers
  include TurboghasHelpers
  include HydroMessageJobTestHelpers
  include SecurityProductsEnablement::EnterpriseTestHelpers
  include GitHub::LoggerHelper

  # Fake class which includes the helpers module that we're testing:
  class Helpers
    include Settings::SecurityProducts::RepositoriesHelper
  end

  # Helper method to initialize and memoize an instance of our fake Helpers class:
  def helpers
    @helpers ||= Helpers.new
  end

  fixtures do
    @user = create(:user)
    @user_session = create(:user_session, user: @user)
    @org = create(:organization, admin: @user)

    updated_at = DateTime.now
    create_list(:repository, 5, owner: @org) do |r, _|
      updated_at -= 1.month
      r.update(pushed_at: updated_at)
    end
    create_list(:private_repository, 5, owner: @org) do |r, _|
      updated_at -= 1.month
      r.update(pushed_at: updated_at)
    end
  end

  setup do
    setup_search
    make_searchable(*@org.repositories.to_a)
  end

  teardown do
    teardown_search
  end

  context "#serialized_repositories" do
    test "calculates licenses required if the organization has purchased GHAS" do
      Organization.any_instance.expects(:advanced_security_purchased?).at_least_once.returns(true)

      stubbed_committers_by_repository = @org.repositories.to_a.reduce({}) do |memo, repo|
        memo[repo.id] = repo.public? ? 0 : 1
        memo
      end
      Helpers.any_instance.expects(:licenses_required_for_repositories).returns([true, stubbed_committers_by_repository])
      payload = T.let(nil, T.untyped)
      assert_logged(Body: "searching for repos", "gh.security_products_enablement.query": "") do
        payload = helpers.serialized_repositories(
          organization: @org,
          user: @user,
          user_session: @user_session,
          cap_filter: cap_authorizing_filter,
        )
      end

      refute_empty payload[:repositories]
      assert_equal @org.repositories.count, payload[:total_repository_count]

      repository_payload = payload[:repositories].first
      # We don't care about validating the actual number because licenses_required_for_repositories has its own test:
      refute_nil repository_payload[:licenses_required]
      assert repository_payload[:licenses_required].is_a?(Integer),
        "Expected licenses_required to be an Integer"
    end

    test "doesn't calculate licenses required if the organization hasn't purchased GHAS" do
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)
      Helpers.any_instance.expects(:licenses_required_for_repositories).never

      payload = helpers.serialized_repositories(
        organization: @org,
        user: @user,
        user_session: @user_session,
        cap_filter: cap_authorizing_filter,
      )

      refute_empty payload[:repositories]
      assert_equal @org.repositories.count, payload[:total_repository_count]

      repository_payload = payload[:repositories].first
      assert_nil repository_payload[:licenses_required]
    end
  end

  context "#licenses_required_for_repositories" do
    test "returns licenses required for repositories" do
      stubbed_committers_by_repository = @org.repositories.to_a.reduce({}) do |memo, repo|
        memo[repo.id] = repo.public? ? 0 : 1
        memo
      end

      Helpers.any_instance.expects(:licenses_required_for_repositories).returns([true, stubbed_committers_by_repository])
      repositories = @org.repositories.to_a

      required_license_stub_data = repositories.collect do |r|
        number_of_licenses = r.public? ? 0 : 1
        [r.id, number_of_licenses]
      end
      stub_licenses_required_result(Hash[required_license_stub_data])

      success, licenses = helpers.licenses_required_for_repositories(repositories)
      assert success, "Expected licenses_required_for_repositories request to succeed"
      assert_equal Hash[required_license_stub_data], licenses
    end

    test "returns when a TurboGHAS failure is encountered" do
      AdvancedSecurityLicense.any_instance
        .stubs(:additional_committers_per_repository)
        .raises(GitHub::Turboghas::ResponseError.new("Something bad happened!"))

      success, licenses = helpers.licenses_required_for_repositories(@org.repositories.to_a)
      refute success, "Expected licenses_required_for_repositories request to fail"
      assert_equal({}, licenses)
    end

    test "returns when a Faraday failure is encountered" do
      AdvancedSecurityLicense.any_instance
        .stubs(:additional_committers_per_repository)
        .raises(Faraday::ConnectionFailed.new("The Internet is broken!"))

      success, licenses = helpers.licenses_required_for_repositories(@org.repositories.to_a)
      refute success, "Expected licenses_required_for_repositories request to fail"
      assert_equal({}, licenses)
    end
  end

  context "#find_repo_ids_by_query" do
    test "logs" do
      assert_logged(Body: "searching for repos", "gh.security_products_enablement.query": "visibility:private,public sort:updated") do
        helpers.find_repo_ids_by_query(
          query: "visibility:private,public sort:updated",
          organization: @org,
          actor: @user,
          user_session: @user_session,
          cap_filter: nil,
          per_page: 4
        )
      end
    end
  end
end
