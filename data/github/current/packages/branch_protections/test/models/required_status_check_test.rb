# typed: true
# frozen_string_literal: true

require "test_helper"

class RequiredStatusCheckTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @org = create(:organization, admin: @owner)

    @repo = create(:repository, owner: @owner, from_example: :simple)

    @org_repo = create(:repository, owner: @org, from_example: :simple)

    branch_attributes = {
      name: "master",
      creator: @owner,
      required_status_checks_enforcement_level: :non_admins,
    }
    @protected_branch = @repo.protected_branches.create(branch_attributes)
    @org_protected_branch = @org_repo.protected_branches.create(branch_attributes)
  end

  test "context is encoded properly as utf8" do
    context_emoji = "Ship it 🚀"
    context_hex = "Ship it \xF0\x9F\x9A\x80"
    context2 = "Ship it 🐿️"

    status_check = RequiredStatusCheck.create(
      protected_branch: @protected_branch,
      context: context_emoji)

    assert_equal context_emoji, status_check.context
    assert_equal Encoding::UTF_8, status_check.context.encoding

    status_check.reload

    status_check.context = context_hex
    assert_equal context_hex, status_check.context
    assert_empty status_check.changes
    refute_predicate status_check, :changed?
    refute_predicate status_check, :context_changed?

    status_check.reload

    status_check.context = context2
    refute_empty status_check.changes
    assert_predicate status_check, :changed?
    assert_predicate status_check, :context_changed?

    # Previously had a bug where the pluck was not returning the proper encoding
    # https://github.com/github/c2c-actions-checks/issues/285
    context_from_pluck = RequiredStatusCheck.where(protected_branch_id: @protected_branch).pluck(:context).first
    assert_equal context_emoji, context_from_pluck
    assert_equal Encoding::UTF_8, context_from_pluck.encoding
  end

  test "valid with plain text context" do
    status_check = RequiredStatusCheck.new(
      protected_branch: @protected_branch,
      context: "plain text",
    )
    assert_predicate status_check, :valid?
  end

  test "valid with emoji context" do
    status_check = RequiredStatusCheck.new(
      protected_branch: @protected_branch,
      context: "emoji #{GRIN_EMOJI}",
    )
    assert_predicate status_check, :valid?
    assert status_check.save
  end

  test "invalid without protected branch" do
    status_check = RequiredStatusCheck.new(
      protected_branch: nil,
      context: "a context",
    )
    refute_predicate status_check, :valid?
    assert status_check.errors[:repository]
  end

  test "invalid without context" do
    status_check = RequiredStatusCheck.new(
      protected_branch: @protected_branch,
      context: nil,
    )
    refute_predicate status_check, :valid?
    assert status_check.errors[:context]
  end

  test "invalid when context is too long" do
    expected_bytes = RequiredStatusCheck::MAXIMUM_CONTEXT_BYTESIZE
    long_string = "*" * (RequiredStatusCheck::MAXIMUM_CONTEXT_BYTESIZE + 1)

    status_check = RequiredStatusCheck.new(
      protected_branch: @protected_branch,
      context: long_string,
    )

    refute_predicate status_check, :valid?
    assert status_check.errors[:context]
    assert_equal status_check.errors.full_messages[0], "Context is too long (maximum is #{expected_bytes / 4} characters)"
  end

  test "invalid when context already exists for branch" do
    status_check = RequiredStatusCheck.create!(
      protected_branch: @protected_branch,
      context: "a context",
    )
    assert RequiredStatusCheck.where(protected_branch_id: @protected_branch, context: "a context").any?

    status_check = RequiredStatusCheck.new(
      protected_branch: @protected_branch,
      context: "a context",
    )
    refute_predicate status_check, :valid?
    assert status_check.errors[:context]

    status_check = RequiredStatusCheck.new(
      protected_branch: @protected_branch,
      context: "a context".upcase,
    )
    assert_predicate status_check, :valid?
    assert status_check.errors[:context].empty?
  end

  test "limits number of contexts per branch" do
    max = 1
    RequiredStatusCheck.stub_const(:MAX_PER_BRANCH, max) do
      assert_equal 0, @protected_branch.required_status_checks.count
      @protected_branch.required_status_checks.create! context: "context1"
      assert_equal max, @protected_branch.required_status_checks.count

      status_check = @protected_branch.required_status_checks.create(context: "context2")
      refute_predicate status_check, :valid?
    end
  end

  test "removed when destroying protected branch" do
    protected_branch = @repo.protected_branches.create(name: "cr-line-endings", creator: @owner)
    protected_branch.required_status_checks.create(context: "a context")

    assert_equal 1, RequiredStatusCheck.where(protected_branch_id: protected_branch.id).count
    assert_equal 1, protected_branch.required_status_checks.reload.count

    perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
      protected_branch.destroy
    end

    assert_equal 0, RequiredStatusCheck.where(protected_branch_id: protected_branch.id).count
    assert_equal 0, protected_branch.required_status_checks.reload.count
  end

  test "instruments create on a repo owned by a user" do
    events = subscribe "required_status_check.create"
    @protected_branch.replace_status_contexts("master")
    required_status_checks = @protected_branch.required_status_checks

    expected_payload = {
      protected_branch_id: @protected_branch.id,
      protected_branch_name: @protected_branch.name,
      required_status_check_id: required_status_checks.first.id,
      repo: @repo.nwo,
      repo_id: @repo.id,
      public_repo: @repo.public?,
      context: "master",
    }

    assert event = events.pop, "expected event"
    assert_equal expected_payload, event.payload
  end

  test "instruments create on a repo owned by an org" do
    events = subscribe "required_status_check.create"
    @org_protected_branch.replace_status_contexts("master")
    required_status_checks = @org_protected_branch.required_status_checks

    expected_payload = {
      protected_branch_id: @org_protected_branch.id,
      protected_branch_name: @org_protected_branch.name,
      required_status_check_id: required_status_checks.first.id,
      repo: @org_repo.nwo,
      repo_id: @org_repo.id,
      public_repo: @org_repo.public?,
      org: @org.name,
      org_id: @org.id,
      context: "master",
    }

    assert event = events.pop, "expected event"
    assert_equal expected_payload, event.payload
  end

  test "instruments destroy on a repo owned by a user" do
    events = subscribe "required_status_check.destroy"
    @protected_branch.replace_status_contexts(["master"])
    required_status_checks = @protected_branch.required_status_checks

    required_status_checks.first.destroy

    expected_payload = {
      protected_branch_id: @protected_branch.id,
      protected_branch_name: @protected_branch.name,
      required_status_check_id: required_status_checks.first.id,
      repo: @repo.nwo,
      repo_id: @repo.id,
      public_repo: @repo.public?,
      context: "master",
    }

    assert event = events.pop, "expected event"
    assert_equal expected_payload, event.payload
  end

  test "instruments destroy on a repo owned by an org" do
    events = subscribe "required_status_check.destroy"
    @org_protected_branch.replace_status_contexts(["master"])
    required_status_checks = @org_protected_branch.required_status_checks

    required_status_checks.first.destroy

    expected_payload = {
      protected_branch_id: @org_protected_branch.id,
      protected_branch_name: @org_protected_branch.name,
      required_status_check_id: required_status_checks.first.id,
      repo: @org_repo.nwo,
      repo_id: @org_repo.id,
      public_repo: @org_repo.public?,
      org: @org.name,
      org_id: @org.id,
      context: "master",
    }

    assert event = events.pop, "expected event"
    assert_equal expected_payload, event.payload
  end

  test "it satisfies the interface required by StatusCheckRollup" do
    StatusCheckRollup::REQUIRED_DUCK_TYPE_METHODS.each do |method|
      assert RequiredStatusCheck.new.respond_to?(method), "Expected Status to respond to #{method.inspect} to satisfy the duck type for StatusCheckRollup"
    end
  end

  context ".pluck_contexts_and_integrations" do
    test "returns a Hash of contexts and their associated integrations" do
      integration = create(:integration)
      RequiredStatusCheck.create!(
        protected_branch: @protected_branch,
        context: "tests",
      )
      RequiredStatusCheck.create!(
        protected_branch: @protected_branch,
        integration: integration,
        context: "ruby-linters",
      )
      RequiredStatusCheck.create!(
        protected_branch: @protected_branch,
        integration: integration,
        context: "js-linters",
      )

      assert_equal(
        { "tests" => Set[], "ruby-linters" => Set[integration], "js-linters" => Set[integration] },
        RequiredStatusCheck.pluck_contexts_and_integrations(@protected_branch.required_status_checks),
      )
    end
  end
end
