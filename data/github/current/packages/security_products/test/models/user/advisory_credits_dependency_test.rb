# typed: true
# frozen_string_literal: true

require "test_helper"

class AdvisoryCreditsDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @vulnerability = create(:published_vulnerability)
  end

  setup_once do
    setup_search
  end

  teardown_once do
    teardown_search
  end

  context "#global_advisory_credit_count" do
    test "returns the number of credits on global advisories" do
      create(:advisory_credit, :accepted, recipient: @user, vulnerability: @vulnerability)
      make_searchable(@vulnerability)

      assert_equal 1, @user.global_advisory_credit_count
    end

    test "only includes credits for the credited user" do
      create(:advisory_credit, :accepted, recipient: @user, vulnerability: @vulnerability)
      create(:advisory_credit, :accepted, vulnerability: @vulnerability)
      make_searchable(@vulnerability)

      assert_equal 1, @user.global_advisory_credit_count
    end

    test "excludes repository advisory credits only" do
      repository_advisory = create(:published_repository_advisory)
      create(:advisory_credit, :accepted, recipient: @user, repository_advisory: repository_advisory)

      assert_equal 0, @user.global_advisory_credit_count
    end

    test "excludes pending credits" do
      create(:advisory_credit, :pending, recipient: @user, vulnerability: @vulnerability)
      make_searchable(@vulnerability)

      assert_equal 0, @user.global_advisory_credit_count
    end

    test "excludes declined credits" do
      create(:advisory_credit, :declined, recipient: @user, vulnerability: @vulnerability)
      make_searchable(@vulnerability)

      assert_equal 0, @user.global_advisory_credit_count
    end

    test "excludes credits on non-public vulnerabilities" do
      create(:advisory_credit, :accepted, recipient: @user, vulnerability: @vulnerability)

      assert_equal 0, @user.global_advisory_credit_count
    end
  end
end
