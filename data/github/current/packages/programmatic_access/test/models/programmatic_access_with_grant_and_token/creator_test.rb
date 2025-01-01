# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class ProgrammaticAccessWithGrantAndToken::CreatorTest < GitHub::TestCase
  include PermissionsHelper

  fixtures do
    @user = create(:user)
  end

  def described_class
    ::ProgrammaticAccessWithGrantAndToken::Creator
  end

  test "creates a new user programmatic access with grant and token" do
    result = assert_difference "UserProgrammaticAccess.count", 1 do
      assert_difference "UserProgrammaticAccessGrant.count", 1 do
        described_class.perform(
          actor: @user,
          target: @user,
          access_token_attributes: { name: "my pat v2", default_expires_at: "7" },
          entry_point: :test_case
        )
      end
    end

    assert_predicate result, :valid?
    assert_equal result.access.name, "my pat v2"
    assert_equal result.access.owner, @user
    grant = result.access.grant
    assert_predicate grant, :present?
    assert_equal grant.permissions, {}
    assert_equal @user, grant.target
  end

  test "creates a new user programmatic access with grant with permissions and token" do
    repo = create(:repository, :minimal, owner: @user)

    result = assert_difference "UserProgrammaticAccess.count", 1 do
      assert_difference "UserProgrammaticAccessGrant.count", 1 do
        described_class.perform(
          actor: @user,
          target: @user,
          access_token_attributes: { name: "my pat v2", default_expires_at: "7" },
          permissions: { "metadata" => :read, "issues" => :write },
          repositories: [repo],
          repository_selection: :subset,
          entry_point: :test_case
        )
      end
    end

    assert_predicate result, :valid?
    assert_equal "my pat v2", result.access.name
    assert_equal result.access.owner, @user
    grant = result.access.grant
    assert_predicate grant, :present?
    assert_same_hash({ "metadata" => :read, "issues" => :write }, grant.permissions)
    assert_equal @user, grant.target
    assert_equal [repo], grant.repositories
  end

  test "creates a new user programmatic access with a grant request and token" do
    org = create(:organization)
    org.add_member(@user)
    expected_permissions = { "members" => :read, "metadata" => :read }

    result = assert_difference "UserProgrammaticAccess.count", 1 do
      assert_difference "OrganizationProgrammaticAccessGrantRequest.count", 1 do
        described_class.perform(
          actor: @user,
          target: org,
          access_token_attributes: { name: "my pat v2", default_expires_at: "7" },
          permissions: expected_permissions,
          repository_selection: :all,
          request_reason: "I need to see org members",
          entry_point: :test_case
        )
      end
    end

    assert_predicate result, :valid?
    assert_equal "my pat v2", result.access.name
    assert_equal result.access.owner, @user

    assert_nil result.access.grant

    request = result.access.grant_request
    assert_predicate request, :persisted?
    assert_equal org, request.target

    assert_equal "I need to see org members", request.reason
    assert_same_hash expected_permissions, request.permissions
  end

  test "does not create a new user programmatic access when expiration date is greater than the target limit policy", feature_enabled: :personal_access_token_expiration_limit do
    org = create(:organization)
    org.add_member(@user)
    expected_permissions = { "members" => :read, "metadata" => :read }
    org.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 20)

    result = assert_no_difference "UserProgrammaticAccess.count" do
      assert_no_difference "OrganizationProgrammaticAccessGrantRequest.count" do
        described_class.perform(
          actor: @user,
          target: org,
          access_token_attributes: { name: "my pat v2", default_expires_at: "30" },
          permissions: expected_permissions,
          repository_selection: :all,
          request_reason: "I need to see org members",
          entry_point: :test_case
        )
      end
    end

    assert_predicate result.errors, :any?
    refute_predicate result.access, :persisted?
    grant = result.access.grant
    refute_predicate grant, :present?
    assert_includes(result.errors.full_messages, "#{org.display_login} does not allow tokens to be created with expiration above 20 days")
  end

  test "creates a new user programmatic access when expiration date is greater than the target limit policy", feature_disabled: :personal_access_token_expiration_limit do
    org = create(:organization)
    org.add_member(@user)
    expected_permissions = { "members" => :read, "metadata" => :read }
    org.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 20)

    result = assert_difference "UserProgrammaticAccess.count", 1 do
      assert_difference "OrganizationProgrammaticAccessGrantRequest.count", 1 do
        described_class.perform(
          actor: @user,
          target: org,
          access_token_attributes: { name: "my pat v2", default_expires_at: "30" },
          permissions: expected_permissions,
          repository_selection: :all,
          request_reason: "I need to see org members",
          entry_point: :test_case
        )
      end
    end

    assert_predicate result, :valid?
    assert_equal "my pat v2", result.access.name
    assert_equal result.access.owner, @user

    assert_nil result.access.grant

    request = result.access.grant_request
    assert_predicate request, :persisted?
    assert_equal org, request.target

    assert_equal "I need to see org members", request.reason
    assert_same_hash expected_permissions, request.permissions
  end

  test "creates a new user programmatic access when expiration date is allowed by the target limit policy", feature_enabled: :personal_access_token_expiration_limit do
    org = create(:organization)
    org.add_member(@user)
    expected_permissions = { "members" => :read, "metadata" => :read }
    org.set_fine_grained_personal_access_token_expiration_limit(actor: @user, expiration: 20)

    result = assert_difference "UserProgrammaticAccess.count", 1 do
      assert_difference "OrganizationProgrammaticAccessGrantRequest.count", 1 do
        described_class.perform(
          actor: @user,
          target: org,
          access_token_attributes: { name: "my pat v2", default_expires_at: "20" },
          permissions: expected_permissions,
          repository_selection: :all,
          request_reason: "I need to see org members",
          entry_point: :test_case
        )
      end
    end

    assert_predicate result, :valid?
    assert_equal "my pat v2", result.access.name
    assert_equal result.access.owner, @user

    assert_nil result.access.grant

    request = result.access.grant_request
    assert_predicate request, :persisted?
    assert_equal org, request.target

    assert_equal "I need to see org members", request.reason
    assert_same_hash expected_permissions, request.permissions
  end

  test "rolls back the entire transaction if the user programmatic access failed to be written" do
    _pat = create(:user_programmatic_access, owner: @user, name: "same name")
    repo = create(:repository, :minimal, owner: @user)

    Failbot.expects(:report!).never

    result = assert_no_difference "UserProgrammaticAccess.count" do
      assert_no_difference "UserProgrammaticAccessGrant.count" do
        assert_no_difference "Permission.count" do
          described_class.perform(
            actor: @user,
            target: @user,
            access_token_attributes: { name: "same name", default_expires_at: "7" },
            permissions: { "metadata" => :read, "issues" => :write },
            repositories: [repo],
            repository_selection: :subset,
            entry_point: :test_case
          )
        end
      end
    end

    assert_predicate result.errors, :any?
    refute_predicate result.access, :persisted?
    grant = result.access.grant
    refute_predicate grant, :present?
  end

  test "rolls back the entire transaction if permissions failed to be written" do
    Permission.expects(:insert_all!).raises(ActiveRecord::RecordInvalid)

    repo = create(:repository, :minimal, owner: @user)
    result = assert_no_difference "UserProgrammaticAccess.count" do
      assert_no_difference "ProgrammaticAccessBot.count" do
        assert_no_difference "UserProgrammaticAccessGrant.count" do
          assert_no_difference "Permission.count" do
            described_class.perform(
              actor: @user,
              target: @user,
              access_token_attributes: { name: "my pat v2", default_expires_at: "7" },
              permissions: { "metadata" => :read, "issues" => :write },
              repositories: [repo],
              repository_selection: :subset,
              entry_point: :test_case
            )
          end
        end
      end
    end

    assert_predicate result.errors, :any?
    refute_predicate result.access, :persisted?
    grant = result.access.grant
    refute_predicate grant, :present?
  end

  test "attempts to generate a token and exposes the result" do
    stubbed_token_result = ProgrammaticAccessToken::Result.success("abc")
    ProgrammaticAccessToken.expects(:generate).returns(stubbed_token_result)

    result = described_class.perform(
      actor: @user,
      target: @user,
      access_token_attributes: { name: "my pat v2", default_expires_at: "7" },
      entry_point: :test_case
    )

    assert_equal stubbed_token_result, result.token_result
    assert_predicate result.token_result, :success?
  end

  test "creates a new user programmatic access even if authnd fails" do
    stubbed_token_result = ProgrammaticAccessToken::Result.failed("boom")
    ProgrammaticAccessToken.expects(:generate).returns(stubbed_token_result)

    result = assert_difference "UserProgrammaticAccess.count", 1 do
      assert_difference "UserProgrammaticAccessGrant.count", 1 do
        described_class.perform(
          actor: @user,
          target: @user,
          access_token_attributes: { name: "my pat v2", default_expires_at: "7" },
          entry_point: :test_case
        )
      end
    end

    assert_predicate result.errors, :empty?
    assert_predicate result.access, :persisted?

    assert_equal stubbed_token_result, result.token_result
    assert_predicate result.token_result, :failed?
  end

  test "it does instrument a successful creation" do
    UserProgrammaticAccess.any_instance.expects(:instrument_creation)

    result = described_class.perform(
      actor: @user,
      target: @user,
      access_token_attributes: { name: "my pat v2", default_expires_at: "7" },
      entry_point: :test_case
    )

    assert_predicate result.errors, :empty?
  end

  test "it does not instrument a failed creation attempt" do
    UserProgrammaticAccess.any_instance.expects(:instrument_creation).never

    result = described_class.perform(
      actor: @user,
      target: @user,
      entry_point: :test_case
    )

    assert_predicate result.errors, :any?
  end

  test "notifies the owner after successful creation" do
    UserProgrammaticAccess.any_instance.expects(:notify_owner).with(about: :created)

    result = described_class.perform(
      actor: @user,
      target: @user,
      access_token_attributes: {
        name: "my pat v2",
        default_expires_at: "7"
      },
      entry_point: :test_case
    )

    assert_predicate result.errors, :empty?
  end

  test "skips notification to the owner on failed creation" do
    UserProgrammaticAccess.any_instance.expects(:notify_owner).never

    result = described_class.perform(
      actor: @user,
      target: @user,
      entry_point: :test_case
    )

    assert_predicate result.errors, :any?
  end

  test "skips notification to the owner when PAT is auto-approved" do
    UserProgrammaticAccess
      .expects(:notify_owner)
      .with(about: :request_approved)
      .never

    result = described_class.perform(
      actor: @user,
      target: @user,
      access_token_attributes: {
        name: "my pat v2",
        default_expires_at: "7"
      },
      entry_point: :test_case
    )

    assert_predicate result.errors, :empty?
  end

  test "skip report when exception is related to name duplication" do
    UserProgrammaticAccess.any_instance.expects(:save!).raises(ActiveRecord::RecordNotUnique)
    Failbot.expects(:report!).never

    result = described_class.perform(
      actor: @user,
      target: @user,
      access_token_attributes: { name: "fast clicker", default_expires_at: "7" },
      permissions: { "metadata" => :read },
      repository_selection: :all,
      entry_point: :test_case
    )

    assert_predicate result.errors, :any?
    refute_predicate result.access, :persisted?
    grant = result.access.grant
    refute_predicate grant, :present?
  end

end
