# typed: true
# frozen_string_literal: true

require "test_helper"

class BotableTest < GitHub::TestCase
  class FakeBot
    include Botable
  end

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @subject = FakeBot.new
  end

  test "#slug raises a NotImplementedError" do
    assert_raises NotImplementedError do
      @subject.slug
    end
  end

  test "#slug= raises a NotImplementedError" do
    assert_raises NotImplementedError do
      @subject.slug = "foo"
    end
  end

  test "#github_owned? returns false" do
    refute_predicate @subject, :github_owned?
  end

  test "#instrument_user_signup is a no-op" do
    assert_nil @subject.instrument_user_signup
  end

  test "#instrument_deletion is a no-op" do
    assert_nil @subject.instrument_deletion
  end

  test "#instrument_async_delete? returns false" do
    refute_predicate @subject, :instrument_async_delete?
  end

  test "#ability_delegate returns nothing by default" do
    assert_nil @subject.ability_delegate
  end

  test "#password_required? returns false" do
    refute_predicate @subject, :password_required?
  end

  test "#email_address_required? returns false" do
    refute_predicate @subject, :email_address_required?
  end

  test "#user? returns false" do
    refute_predicate @subject, :user?
  end

  test "#organization? returns false" do
    refute_predicate @subject, :organization?
  end

  test "#bot? returns true" do
    assert_predicate @subject, :bot?
  end

  test "#mannequin? returns false" do
    refute_predicate @subject, :mannequin?
  end

  test "#restricts_oauth_applications? returns false" do
    refute_predicate @subject, :restricts_oauth_applications?
  end

  test "#billable? returns false" do
    refute_predicate @subject, :billable?
  end

  test "cannot auth via oauth" do
    refute_predicate @subject, :can_authenticate_via_oauth?
  end

  test "can auth via basic auth" do
    assert_predicate @subject, :can_authenticate_via_basic_auth?
  end

  test "cannot auth via username and password basic auth" do
    refute_predicate @subject, :can_authenticate_via_username_password_basic_auth?
  end

  test "#can_have_granular_permissions? is bound by the ability delegate" do
    @subject.stubs(:ability_delegate).returns(IntegrationInstallation.new)

    assert_predicate @subject.ability_delegate, :can_have_granular_permissions?
    assert_predicate @subject, :can_have_granular_permissions?
  end

  test "#authenticated_by_password?" do
    refute_predicate @subject, :authenticated_by_password?
  end

  test "cannot be assigned to an issue" do
    refute_predicate @subject, :assignable_to_issues?
  end

  test "cannot receive notifications" do
    refute_predicate @subject, :newsies_enabled?
  end

  test "cannot own repositories" do
    refute_predicate @subject, :can_own_repositories?
  end

  test "does not receive email confirmation when destroyed" do
    refute_predicate @subject, :receives_confirmation_when_destroyed?
  end

  test "#searchable?" do
    refute_predicate @subject, :searchable?
  end

  test "#require_email_verification? returns false" do
    refute_predicate @subject, :require_email_verification?
  end

  context "#associated_repository_ids" do
    test "returns nothing if the ability delegate defined but not set" do
      @subject.stubs(:ability_delegate).returns(nil)
      assert_empty @subject.associated_repository_ids
    end

    test "returns the ability delegate's #repository_ids" do
      repo = create(:repository, :minimal, owner: create(:user))

      installation = make_integration_installation(repository: repo, permissions: { "metadata" => :read })
      @subject.stubs(:ability_delegate).returns(installation)

      assert_same_elements [repo.id], @subject.ability_delegate.repository_ids
      assert_same_elements [repo.id], @subject.associated_repository_ids
    end
  end

  test "#validates_login_format?" do
    refute_predicate @subject, :validates_login_format?
  end
end
