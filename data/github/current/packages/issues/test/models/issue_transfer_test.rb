# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueTransferTest < GitHub::TestCase
  include NewsiesHelper
  include HookIntegrationTestHelper
  include HydroTestHelpers
  include UploadableTestHelpers
  include HydroTestHelpers
  include GitHub::LoggerHelper

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    User.create_ghost
    @owner = create(:user)
    @member = create(:user)
    @member2 = create(:user, login: "member2")
    @noncollab = create(:user)
    @org = create(:organization)
    @org.add_member(@owner, action: :admin)
    @org.add_member(@member, action: :write)
    @org.add_member(@member2, action: :write)
    @old_repository = create(:repository, owner: @org, created_by_user_id: @owner.id)
    @new_repository = create(:repository, owner: @org, created_by_user_id: @owner.id)
    @issue = create(:issue, :subscribed_author, title: "Transfer me", user: @member, repository: @old_repository, create_references: true)
    @issue2 = create(:issue, title: "Transfer me too", user: @member, repository: @old_repository, create_references: true)

    @old_repo_hook = create :hook, :web, installation_target: @old_repository, events: %w(*)
    @new_repo_hook = create :hook, :web, installation_target: @new_repository, events: %w(*)
    @org_hook = create :hook, :org, installation_target: @org, events: %w(issues)

    @all_notification_jobs = [
      Newsies::DeliverNotificationsJob,
      NotifySubscriptionStatusChangeJob,
      AsyncNewsiesDeliveryJob,
      UpdateSubscriptionsAndNotifyJob,
      SubscribeAndNotifyJob,
      DeliverHookEventJob,
      Notifyd::PublishNotifyMessageJob]

    @deliveries = subscribe_to_hook_delivery "issues"
  end

  TRANSFERRABLE_EVENTS = %w(
    closed
    reopened
    mentioned
    subscribed
    unsubscribed
    referenced
    assigned
    unassigned
    locked
    unlocked
    renamed
    deployed
    deployment_environment_changed
    base_ref_force_pushed
    head_ref_force_pushed
    comment_deleted
    marked_as_duplicate
    unmarked_as_duplicate
    transferred
    pinned
    unpinned
    user_blocked
    labeled
    unlabeled
    milestoned
    demilestoned
    connected
    disconnected
  ).freeze

  test "can be done when actor has admin access to both repositories" do
    transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
    transfer.transfer!
    transfer.save!

    assert transfer.new_issue
  end

  test "can be done when actor has write access to both repositories" do
    @old_repository.add_member(@member, action: :write)
    @new_repository.add_member(@member, action: :write)
    transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @member)
    transfer.transfer!
    transfer.save!

    assert transfer.new_issue
  end

  test "cannot be done when old repo is private and new repo is public" do
    private_repository = create(:private_repository, owner: @org, created_by_user_id: @owner.id)
    issue = create(
      :issue,
      title: "you can't transfer me",
      user: @member,
      repository: private_repository,
    )

    transfer = IssueTransfer.new(old_issue: issue, old_repository: issue.repository, new_repository: @new_repository, actor: @owner)

    refute_predicate transfer, :valid?
    assert transfer.errors[:old_issue].present?
  end

  test "cannot be done when owner doesn't have write access to old repository" do
    transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: create(:user))
    refute_predicate transfer, :valid?
    assert transfer.errors[:actor].present?
  end

  test "cannot be done if the new repo is within a different organization than the current repo is" do
    other_org = create(:organization)
    new_repository = create(:repository, owner: other_org, created_by_user_id: @owner.id)
    transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: new_repository, actor: @owner)
    refute_predicate transfer, :valid?
    assert transfer.errors[:new_repository].present?
  end

  test "cannot be done when issue is locked" do
    @issue.lock(@owner)
    transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
    refute_predicate transfer, :valid?
    assert transfer.errors[:old_issue].present?
  end

  test "cannot be done when issue is a pull request" do
    example_repo :pull_request_source, @old_repository
    pull =
      create(:pull_request,
        repository:      @old_repository,
        base_repository: @old_repository,
        base_user:       @old_repository.owner,
        base_ref:        "master",
        head_repository: @old_repository,
        head_user:       @issue.user,
        head_ref:        "master-merged-topic",
        issue:           @issue,
        )
    transfer = IssueTransfer.new(old_issue: pull.issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
    refute_predicate transfer, :valid?
    assert transfer.errors[:old_issue].present?
  end

  test "works when issue's user was deleted" do
    @issue.user = user = create(:user)
    @issue.save!
    assert user.destroy, "User should be destroyed"
    @issue = Issue.find(@issue.id)
    assert_equal User.ghost, @issue.safe_user, "The issue's safe user should be Ghost since the author was deleted"

    transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
    transfer.transfer!
    transfer.save!

    assert transfer.new_issue, "expect the new issue to be present on the transfer object"
    new_issue = Issue.find(T.must(T.must(transfer.new_issue).id))

    assert_equal User.ghost, new_issue.safe_user, "Transferred issue's new safe user should be Ghost"
  end

  test "cannot be done when repository has interaction limitations" do
    ability = RepositoryInteractionAbility.new(@new_repository)
    assert ability.set_ability(:contributors_only, @new_repository.owner)

    issue = create(:issue, title: "Transfer me", user: @noncollab, repository: @old_repository)
    transfer = IssueTransfer.new(old_issue: issue, old_repository: issue.repository, new_repository: @new_repository, actor: @owner)
    if !GitHub.enterprise?
      assert_raises ActiveRecord::RecordInvalid do
        transfer.transfer!
      end
    end
  end

  test "can be done when repository has interaction limitations and modifiying user is allows" do
    ability = RepositoryInteractionAbility.new(@new_repository)
    assert ability.set_ability(:contributors_only, @new_repository.owner)
    GitHub.context.push(actor_id: @owner.id)

    issue = create(:issue, title: "Transfer me", user: @noncollab, repository: @old_repository)
    transfer = IssueTransfer.new(old_issue: issue, old_repository: issue.repository, new_repository: @new_repository, actor: @owner)

    transfer.transfer!
    transfer.save!

    assert transfer.new_issue
  end

  test "cannot be done if old repo is archived" do
    @old_repository.update(maintained: false)
    transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
    refute_predicate transfer, :valid?
    assert transfer.errors[:old_repository].present?
  end

  test "cannot be done if new repo is archived" do
    @new_repository.update(maintained: false)
    transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
    refute_predicate transfer, :valid?
    assert transfer.errors[:new_repository].present?
  end

  test "cannot be done if old repo has issues disabled" do
    @old_repository.update(has_issues: false)
    transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
    refute_predicate transfer, :valid?
    assert transfer.errors[:old_repository].present?
  end

  test "cannot be done if new repo has issues disabled" do
    @new_repository.update(has_issues: false)
    transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
    refute_predicate transfer, :valid?
    assert transfer.errors[:new_repository].present?
  end

  context ".find_from" do
    test "returns nil when there's no transfer" do
      assert_nil IssueTransfer.find_from(repository: create(:repository, created_by_user_id: @owner.id), number: "123")
    end

    test "finds the issue_transfer when there's one redirect" do
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!

      assert_equal transfer, IssueTransfer.find_from(repository: @old_repository, number: @issue.number)
    end

    test "finds the issue_transfer when there's two redirects" do
      new_new_repository = create(:repository, owner: @org, created_by_user_id: @owner.id)

      first_transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      first_transfer.transfer!

      transfer = IssueTransfer.new(old_issue: first_transfer.new_issue, old_repository: @new_repository, new_repository: new_new_repository, actor: @owner)
      transfer.transfer!

      assert_equal transfer, IssueTransfer.find_from(repository: @old_repository, number: @issue.number)
    end

    test "returns nil when number of redirects exceeds number of transfers" do
      new_new_repository = create(:repository, owner: @org, created_by_user_id: @owner.id)

      first_transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      first_transfer.transfer!

      transfer = IssueTransfer.new(old_issue: first_transfer.new_issue, old_repository: @new_repository, new_repository: new_new_repository, actor: @owner)
      transfer.transfer!

      IssueTransfer.stub_const(:DEFAULT_TRANSFER_TRAVERSAL_DEPTH, 1) do
        assert_nil IssueTransfer.find_from(repository: @old_repository, number: @issue.number)
      end
    end
  end

  context ".find_new_id_by_original_id" do
    test "returns nil when there's no transfer" do

      assert_nil IssueTransfer.find_new_id_by_original_id(original_id: create(:issue).id)
    end

    test "finds the issue_transfer when there's one redirect" do
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!

      assert_equal transfer.new_issue_id, IssueTransfer.find_new_id_by_original_id(original_id: @issue.id)
    end

    test "finds the issue_transfer when there's two redirects" do
      new_new_repository = create(:repository, owner: @org, created_by_user_id: @owner.id)

      first_transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      first_transfer.transfer!

      transfer = IssueTransfer.new(old_issue: first_transfer.new_issue, old_repository: @new_repository, new_repository: new_new_repository, actor: @owner)
      transfer.transfer!

      assert_equal transfer.new_issue_id, IssueTransfer.find_new_id_by_original_id(original_id: @issue.id)
    end

    test "returns nil when number of redirects exceeds number of transfers" do
      new_new_repository = create(:repository, owner: @org, created_by_user_id: @owner.id)

      first_transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      first_transfer.transfer!

      transfer = IssueTransfer.new(old_issue: first_transfer.new_issue, old_repository: @new_repository, new_repository: new_new_repository, actor: @owner)
      transfer.transfer!

      IssueTransfer.stub_const(:DEFAULT_TRANSFER_TRAVERSAL_DEPTH, 1) do
        assert_nil IssueTransfer.find_new_id_by_original_id(original_id: @issue.id)
      end
    end
  end

  context "#transfer!" do
    test "creates new issue to another repository" do
      @issue.update_columns(performed_by_integration_id: 123, state: "closed", closed_at: 1.day.ago, created_at: 1.week.ago)
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!
      new_issue = T.must(transfer.new_issue)

      assert_equal @issue.title, new_issue.title
      assert_equal @issue.user_id, new_issue.user_id
      assert_equal @issue.issue_comments_count, new_issue.issue_comments_count
      assert_equal @issue.state, new_issue.state
      assert_equal @issue.user_hidden, new_issue.user_hidden
      assert_equal @issue.performed_by_integration_id, new_issue.performed_by_integration_id
      assert_equal new_issue.transfer, true
      assert_equal @issue.closed_at, new_issue.closed_at
      assert_equal @issue.created_at, new_issue.created_at
    end

    test "transfers the issue type if the FF is enabled" do
      GitHub.flipper[:issue_types].enable

      issue_type = @org.issue_types.first
      @issue.issue_type = issue_type
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!
      new_issue = T.must(transfer.new_issue)

      assert_equal @issue.issue_type, new_issue.issue_type
    end

    test "Doesn't transfer the issue type if the FF is disabled" do
      GitHub.flipper[:issue_types].disable

      issue_type = @org.issue_types.first
      @issue.issue_type = issue_type
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!
      new_issue = T.must(transfer.new_issue)

      assert_nil new_issue.issue_type
    end

    test "Doesn't transfer the issue type if the issue type is private, and the repository is public", skip_with_all_emus: true do
      GitHub.flipper[:issue_types].enable
      issue_type = create(:issue_type, owner: @org, private: true, enabled: true)

      @issue.issue_type = issue_type

      repository = create(:public_repository, owner: @org, created_by_user_id: @owner.id)

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: repository, actor: @owner)
      transfer.transfer!
      new_issue = T.must(transfer.new_issue)

      assert_nil new_issue.issue_type
    end

    test "updates CloseIssueReferences" do
      ref = create(:close_issue_reference, issue: @issue, issue_repository: @issue.repository)
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository,
                                   new_repository: @new_repository, actor: @owner)

      assert_no_difference("CloseIssueReference.count") do
        transfer.transfer!
      end

      new_issue = @new_repository.issues.find_by(title: "Transfer me")
      assert_equal new_issue, ref.reload.issue
      assert_equal @new_repository, ref.issue_repository
    end

    test "transfers manual CloseIssueReferences" do
      ref = create(:manual_close_issue_reference, issue: @issue)
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository,
                                   new_repository: @new_repository, actor: @owner)

      assert_no_difference("CloseIssueReference.count") do
        perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { transfer.transfer! }
      end

      new_issue = @new_repository.issues.find_by(title: "Transfer me")
      assert new_issue.close_issue_references.manual
    end

    test "Transfer issue xrefs are transferred" do
      issue_1 = @issue
      issue_2 = create :issue, title: "Transfer me!", user: @owner, repository: @old_repository
      issue_2.update!(body: "This is related to ##{issue_1.number}")
      create_comment(issue: issue_2, body: "This is related to ##{issue_1.number}", user: @user)

      @issue.update!(body: "This is related to ##{issue_2.number}")
      create_comment(issue: issue_1, body: "This is related to ##{issue_2.number}", user: @user)

      issue_1.reload
      issue_2.reload

      pre_transfer_update_count = hydro_message_count(schema: "github.v1.IssueUpdate")
      transfer = IssueTransfer.new(old_issue: issue_2, old_repository: issue_2.repository,
        new_repository: @new_repository, actor: @owner)

      jobs = @all_notification_jobs + [TransferIssueJob]
      perform_enqueued_jobs(only: jobs) { transfer.async_transfer! }

      new_issue_2 = @new_repository.issues.find_by(id: T.must(transfer.new_issue).id)
      issue_1.reload

      assert_equal 1, issue_1.references.size
      assert_equal 0, issue_2.references.size
      assert_equal 1, new_issue_2.references.size

      assert_equal new_issue_2.id, issue_1.references.first.source.id
      assert_equal new_issue_2.repository.id, issue_1.references.first.source_repository_id
      assert_equal new_issue_2.repository_id, issue_1.references.first.source.repository_id

      assert_equal @old_repository.id, issue_1.references.first.target.repository_id
      assert_equal @old_repository.id, issue_1.references.first.target_repository_id

      assert_equal issue_1.id, new_issue_2.references.first.source.id
      assert_equal issue_1.repository_id, new_issue_2.references.first.source.repository_id
      assert_equal issue_1.repository_id, new_issue_2.references.first.source_repository_id

      assert_equal @new_repository.id, new_issue_2.references.first.target.repository_id
      assert_equal @new_repository.id, new_issue_2.references.first.target_repository_id

      assert_expected_notifications(pre_transfer_update_count)
    end

    test "Transfer issue xrefs are transferred when not circular reference" do
      # issue 1 references issue 2, which references issue 3.
      issue_1 = @issue
      issue_2 = create :issue, title: "Transfer me!", user: @owner, repository: @old_repository, create_references: true
      perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) { issue_1.update!(body: "This is related to ##{issue_2.number}") }

      issue_3 = create :issue, title: "Don't transfer me!", user: @owner, repository: @old_repository, create_references: true

      perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) { issue_2.update!(body: "This is related to ##{issue_3.number}") }

      issue_3_reference_created_at = Time.new(2002)
      issue_3.references.first.update_column(:created_at, issue_3_reference_created_at)

      issue_1.reload
      issue_2.reload
      issue_3.reload

      pre_transfer_update_count = hydro_message_count(schema: "github.v1.IssueUpdate")
      transfer = IssueTransfer.new(old_issue: issue_2, old_repository: issue_2.repository,
        new_repository: @new_repository, actor: @owner)

      jobs = @all_notification_jobs + [TransferIssueJob, DestroyDependentRecordsJob, ProcessMentionedReferencesJob]

      perform_enqueued_jobs(only: jobs) { transfer.async_transfer! }

      new_issue_2 = @new_repository.issues.find_by(id: T.must(transfer.new_issue).id)

      issue_1.reload
      issue_3.reload

      assert_equal 0, issue_1.references.size
      assert_equal 0, issue_2.references.size

      assert_equal 1, new_issue_2.references.size

      assert_equal 1, issue_3.references.size

      issue_1_to_issue_2_reference = new_issue_2.references.first

      issue_2_to_issue_3_reference = issue_3.references.first

      assert_equal issue_3_reference_created_at, issue_2_to_issue_3_reference.created_at

      assert_equal new_issue_2.id, issue_1_to_issue_2_reference.target.id
      assert_equal new_issue_2.repository_id, issue_1_to_issue_2_reference.target.repository_id
      assert_equal new_issue_2.repository_id, issue_1_to_issue_2_reference.target_repository_id

      assert_equal issue_1.id, issue_1_to_issue_2_reference.source.id
      assert_equal issue_1.repository_id, issue_1_to_issue_2_reference.source.repository_id
      assert_equal issue_1.repository_id, issue_1_to_issue_2_reference.source_repository_id

      assert_equal issue_3.id, issue_2_to_issue_3_reference.target.id
      assert_equal issue_3.repository_id, issue_2_to_issue_3_reference.target.repository_id
      assert_equal issue_3.repository_id, issue_2_to_issue_3_reference.target_repository_id

      assert_equal new_issue_2.id, issue_2_to_issue_3_reference.source.id
      assert_equal new_issue_2.repository_id, issue_2_to_issue_3_reference.source.repository_id
      assert_equal new_issue_2.repository_id, issue_2_to_issue_3_reference.source_repository_id

      assert_expected_notifications(pre_transfer_update_count)
    end

    test "Transfer issue xrefs are transferred when not circular reference, comments in body" do
      # issue 1 references issue 2, which references issue 3.
      issue_1 = @issue
      issue_2 = create :issue, title: "Transfer me!", user: @owner, repository: @old_repository
      create_comment(issue: issue_1, body: "This is related to ##{issue_2.number}", user: @user)

      issue_3 = create :issue, title: "Don't transfer me!", user: @owner, repository: @old_repository
      create_comment(issue: issue_2, body: "This is related to ##{issue_3.number}", user: @user)

      issue_3_reference_created_at = Time.new(2002)
      issue_3.references.first.update_column(:created_at, issue_3_reference_created_at)

      issue_1.reload
      issue_2.reload
      issue_3.reload

      pre_transfer_update_count = hydro_message_count(schema: "github.v1.IssueUpdate")
      transfer = IssueTransfer.new(old_issue: issue_2, old_repository: issue_2.repository,
        new_repository: @new_repository, actor: @owner)

      jobs = @all_notification_jobs + [TransferIssueJob, DestroyDependentRecordsJob, ProcessMentionedReferencesJob]

      perform_enqueued_jobs(only: jobs) { transfer.async_transfer! }

      new_issue_2 = @new_repository.issues.find_by(id: T.must(transfer.new_issue).id)

      issue_1.reload
      issue_3.reload

      assert_equal 0, issue_1.references.size
      assert_equal 0, issue_2.references.size

      assert_equal 1, new_issue_2.references.size

      assert_equal 1, issue_3.references.size

      issue_1_to_issue_2_reference = new_issue_2.references.first

      issue_2_to_issue_3_reference = issue_3.references.first

      assert_equal issue_3_reference_created_at, issue_2_to_issue_3_reference.created_at

      assert_equal new_issue_2.id, issue_1_to_issue_2_reference.target.id
      assert_equal new_issue_2.repository_id, issue_1_to_issue_2_reference.target.repository_id
      assert_equal issue_1.id, issue_1_to_issue_2_reference.source.id
      assert_equal issue_1.repository_id, issue_1_to_issue_2_reference.source.repository_id

      assert_equal issue_3.id, issue_2_to_issue_3_reference.target.id
      assert_equal issue_3.repository_id, issue_2_to_issue_3_reference.target.repository_id
      assert_equal new_issue_2.id, issue_2_to_issue_3_reference.source.id
      assert_equal new_issue_2.repository_id, issue_2_to_issue_3_reference.source.repository_id

      assert_expected_notifications(pre_transfer_update_count)
    end

    test "Transfer issue references copy skips xref with deleted source" do
      issue_1 = @issue
      issue_2 = create :issue, title: "Transfer me!", user: @owner, repository: @old_repository
      issue_2.update!(body: "This is related to ##{issue_1.number}")
      create_comment(issue: issue_2, body: "This is related to ##{issue_1.number}", user: @user)
      @issue.update!(body: "This is related to ##{issue_2.number}")
      create_comment(issue: issue_1, body: "This is related to ##{issue_2.number}", user: @user)

      issue_1.delete
      issue_2.reload

      transfer = IssueTransfer.new(old_issue: issue_2, old_repository: issue_2.repository,
        new_repository: @new_repository, actor: @owner)

      transfer.transfer!
      assert_equal 0, T.must(transfer.new_issue).reload.references.size
    end

    test "Transfer issue copy_referencing_issues_references handles deleted issue source" do
      issue_1 = @issue
      issue_2 = create :issue, title: "Transfer me!", user: @owner, repository: @old_repository
      issue_2.update!(body: "This is related to ##{issue_1.number}")
      create_comment(issue: issue_2, body: "This is related to ##{issue_1.number}", user: @user)

      @issue.update!(body: "This is related to ##{issue_2.number}")
      create_comment(issue: issue_1, body: "This is related to ##{issue_2.number}", user: @user)
      issue_2.reload

      transfer = IssueTransfer.new(old_issue: issue_2, old_repository: issue_2.repository,
        new_repository: @new_repository, actor: @owner)

      transfer.send(:create_copy_issue)
      transfer.send(:copy_references_to_new_issue)

      issue_1.delete
      transfer.reload

      # Manually invoke to validate handling deleted xrefs
      transfer.send(:copy_referencing_issues_references)

      # We expect 1 because :copy_references_to_new_issue was called before deleting
      assert_equal 1, T.must(transfer.new_issue).reload.references.size
    end

    test "updates IssueReferences with repo/number comments" do
      issue_2 = create :issue, title: "I'm staying put", user: @owner, repository: @old_repository
      issue_2.update!(body: "This is related to ##{@issue.number}")
      create_comment(issue: issue_2, body: "This is related to ##{@issue.number}", user: @user)

      @issue.update!(body: "This is related to ##{issue_2.number}")
      create_comment(issue: @issue, body: "This is related to ##{issue_2.number}", user: @user)

      issue_updated_at = @issue.updated_at
      comment_updated_at = @issue.comments.first.updated_at

      @issue.reload
      issue_2.reload

      assert_equal 1, @issue.references.size
      assert_equal 1, issue_2.references.size
      assert_equal 0, @issue.events.size
      assert_equal 0, issue_2.events.size

      issue_ref_time = @issue.references.first.created_at.dup
      issue_2_ref_time = issue_2.references.first.created_at.dup


      transfer = IssueTransfer.new(old_issue: issue_2, old_repository: issue_2.repository,
                                   new_repository: @new_repository, actor: @owner)

      perform_enqueued_jobs(only: TransferIssueJob) { transfer.async_transfer! }

      new_issue_2 = @new_repository.issues.find_by(id: T.must(transfer.new_issue).id)
      @issue.reload

      assert_equal 0, @issue.events.size
      assert_equal 1, new_issue_2.events.size
      assert new_issue_2.events.map(&:event) == ["transferred"]

      assert_equal "This is related to #{@issue.repository.name_with_owner}##{@issue.number}", new_issue_2.body
      assert_equal "This is related to #{@issue.repository.name_with_owner}##{@issue.number}", new_issue_2.comments.first.body

      assert_equal "This is related to #{new_issue_2.repository.name_with_owner}##{new_issue_2.number}", @issue.body
      assert_equal "This is related to #{new_issue_2.repository.name_with_owner}##{new_issue_2.number}", @issue.comments.first.body

      unless GitHub.flipper[:issue_transfer_update_body_with_touch].enabled?
        assert_equal issue_updated_at, @issue.updated_at
        assert_equal comment_updated_at, @issue.comments.first.updated_at
      end

      assert_equal 1, @issue.references.size
      assert_equal 1, new_issue_2.references.size

      ref = new_issue_2.references.first
      assert_equal ref.source_id, @issue.id
      assert_equal ref.target_id, new_issue_2.id
      assert_equal ref.created_at, issue_2_ref_time

      ref = @issue.references.first
      assert_equal ref.source_id, new_issue_2.id
      assert_equal ref.target_id, @issue.id
      assert_equal ref.created_at, issue_ref_time

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository,
        new_repository: @new_repository, actor: @owner)

      perform_enqueued_jobs(only: TransferIssueJob) { transfer.async_transfer! }

      # After 2nd transfer
      new_issue = @new_repository.issues.find_by(id: T.must(transfer.new_issue).id)
      new_issue_2.reload

      assert_equal "This is related to #{new_issue_2.repository.name_with_owner}##{new_issue_2.number}", new_issue.body
      assert_equal "This is related to #{new_issue_2.repository.name_with_owner}##{new_issue_2.number}", new_issue.comments.first.body

      assert_equal "This is related to #{new_issue.repository.name_with_owner}##{new_issue.number}", new_issue_2.body
      assert_equal "This is related to #{new_issue.repository.name_with_owner}##{new_issue.number}", new_issue_2.comments.first.body

      assert_equal 1, new_issue.references.size
      assert_equal 1, new_issue_2.references.size
      ref = new_issue.references.first
      assert_equal ref.source_id, new_issue_2.id
      assert_equal ref.target_id, new_issue.id
      assert_equal ref.created_at, issue_ref_time

      ref = new_issue_2.references.first
      assert_equal ref.source_id, new_issue.id
      assert_equal ref.target_id, new_issue_2.id
      assert_equal ref.created_at, issue_2_ref_time

      assert_equal 0, @issue.events.size
      assert_equal 0, issue_2.events.size
      assert_equal 1, new_issue.events.size
      assert new_issue.events.map(&:event) == ["transferred"]
      assert_equal 1, new_issue_2.events.size
      assert new_issue_2.events.map(&:event) == ["transferred"]
    end

    test "updates IssueReferences with full url references" do
      issue_2 = create :issue, title: "I'm staying put", user: @owner, repository: @old_repository
      issue_2.update!(body: "This is related to https://github.com/#{@issue.repository.nwo}/issues/#{@issue.number}")
      create_comment(issue: issue_2, body: "This is related to https://github.com/#{@issue.repository.nwo}/issues/#{@issue.number}", user: @user)

      @issue.update!(body: "This is related to https://github.com/#{issue_2.repository.nwo}/issues/#{issue_2.number}")
      create_comment(issue: @issue, body: "This is related to https://github.com/#{issue_2.repository.nwo}/issues/#{issue_2.number}", user: @user)

      @issue.reload
      issue_2.reload

      assert_equal 1, @issue.references.size
      assert_equal 1, issue_2.references.size
      assert_equal 0, @issue.events.size
      assert_equal 0, issue_2.events.size

      issue_ref_time = @issue.references.first.created_at
      issue_2_ref_time = issue_2.references.first.created_at

      transfer = IssueTransfer.new(old_issue: issue_2, old_repository: issue_2.repository,
                                   new_repository: @new_repository, actor: @owner)

      transfer.transfer!

      new_issue_2 = @new_repository.issues.find_by(id: T.must(transfer.new_issue).id)
      @issue.reload

      assert_equal 0, @issue.events.size
      assert_equal 1, new_issue_2.events.size
      assert new_issue_2.events.map(&:event) == ["transferred"]

      assert_equal "This is related to https://github.com/#{@issue.repository.nwo}/issues/#{@issue.number}", new_issue_2.body
      assert_equal "This is related to https://github.com/#{@issue.repository.nwo}/issues/#{@issue.number}", new_issue_2.comments.first.body

      assert_equal "This is related to https://github.com/#{new_issue_2.repository.nwo}/issues/#{new_issue_2.number}", @issue.body
      assert_equal "This is related to https://github.com/#{new_issue_2.repository.nwo}/issues/#{new_issue_2.number}", @issue.comments.first.body

      assert_equal 1, @issue.references.size
      assert_equal 1, new_issue_2.references.size

      ref = new_issue_2.references.first
      assert_equal ref.source_id, @issue.id
      assert_equal ref.target_id, new_issue_2.id
      assert_equal ref.created_at, issue_2_ref_time

      ref = @issue.references.first
      assert_equal ref.source_id, new_issue_2.id
      assert_equal ref.target_id, @issue.id
      assert_equal ref.created_at, issue_ref_time

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository,
        new_repository: @new_repository, actor: @owner)

      transfer.transfer!

      # After 2nd transfer
      new_issue = @new_repository.issues.find_by(id: T.must(transfer.new_issue).id)
      new_issue_2.reload

      assert_equal "This is related to https://github.com/#{new_issue_2.repository.nwo}/issues/#{new_issue_2.number}", new_issue.body
      assert_equal "This is related to https://github.com/#{new_issue_2.repository.nwo}/issues/#{new_issue_2.number}", new_issue.comments.first.body

      assert_equal "This is related to https://github.com/#{new_issue.repository.nwo}/issues/#{new_issue.number}", new_issue_2.body
      assert_equal "This is related to https://github.com/#{new_issue.repository.nwo}/issues/#{new_issue.number}", new_issue_2.comments.first.body

      assert_equal 1, new_issue.references.size
      assert_equal 1, new_issue_2.references.size
      ref = new_issue.references.first
      assert_equal ref.source_id, new_issue_2.id
      assert_equal ref.target_id, new_issue.id
      assert_equal ref.created_at, issue_ref_time

      ref = new_issue_2.references.first
      assert_equal ref.source_id, new_issue.id
      assert_equal ref.target_id, new_issue_2.id
      assert_equal ref.created_at, issue_2_ref_time

      assert_equal 0, @issue.events.size
      assert_equal 0, issue_2.events.size
      assert_equal 1, new_issue.events.size
      assert new_issue.events.map(&:event) == ["transferred"]
      assert_equal 1, new_issue_2.events.size
      assert new_issue_2.events.map(&:event) == ["transferred"]
    end

    test "updates IssueReferences with references to self" do
      issue = create :issue, title: "I will reference myself", user: @owner, repository: @old_repository

      body = build_text([issue, issue], [false, true], plain = true)
      issue.update!(body: body)
      issue.reload

      assert_equal 0, issue.references.size
      transfer = IssueTransfer.new(old_issue: issue, old_repository: issue.repository,
                                   new_repository: @new_repository, actor: @owner)

      transfer.transfer!

      new_issue = @new_repository.issues.find_by(id: T.must(transfer.new_issue).id)
      assert_equal 1, new_issue.events.size
      assert_equal 0, new_issue.references.size
      assert_equal 0, issue.references.size
      assert new_issue.events.map(&:event) == ["transferred"]
    end

    test "updates IssueReferences with mixed reference types" do
      issue_1 = create :issue, title: "I1 - I'm staying put", user: @owner, repository: @old_repository
      issue_2 = create :issue, title: "I2 - I'm staying put", user: @owner, repository: @old_repository
      issue_3 = create :issue, title: "I3 - I'm staying put", user: @owner, repository: @old_repository

      body_1 = build_text([issue_2, issue_3, issue_2, issue_3], [false, false, true, true], plain = true)
      body_2 = build_text([issue_1, issue_3, issue_1, issue_3], [false, false, true, true], plain = true)
      body_3 = build_text([issue_1, issue_2, issue_1, issue_2], [false, false, true, true])

      perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) do
        issue_1.update!(body: body_1)
        issue_2.update!(body: body_2)
        issue_3.update!(body: body_3)
      end

      create(:issue_comment, issue: issue_1, body: body_1, user: @user)
      create(:issue_comment, issue: issue_2, body: body_2, user: @user)
      create(:issue_comment, issue: issue_3, body: body_3, user: @user)

      issue_1.reload
      issue_2.reload
      issue_3.reload

      assert_equal 2, issue_1.references.size
      assert_equal 2, issue_2.references.size
      assert_equal 2, issue_3.references.size
      assert_equal 0, issue_1.events.size
      assert_equal 0, issue_2.events.size
      assert_equal 0, issue_3.events.size

      issue_1_ref_times = issue_1.references.map(&:created_at).sort
      issue_2_ref_times = issue_2.references.map(&:created_at).sort
      issue_3_ref_times = issue_3.references.map(&:created_at).sort

      # transfer issue 2
      transfer = IssueTransfer.new(old_issue: issue_2, old_repository: issue_2.repository,
                                   new_repository: @new_repository, actor: @owner)

      transfer.transfer!

      issue_2 = @new_repository.issues.find_by(id: T.must(transfer.new_issue).id)
      issue_1.reload
      issue_3.reload

      assert_equal 0, issue_1.events.size
      assert_equal 1, issue_2.events.size
      assert issue_2.events.map(&:event) == ["transferred"]
      assert_equal 0, issue_3.events.size

      assert_equal build_text([issue_2, issue_3, issue_2, issue_3], [false, false, true, true]), issue_1.body
      assert_equal build_text([issue_2, issue_3, issue_2, issue_3], [false, false, true, true]), issue_1.comments.first.body

      assert_equal build_text([issue_1, issue_3, issue_1, issue_3], [false, false, true, true]), issue_2.body
      assert_equal build_text([issue_1, issue_3, issue_1, issue_3], [false, false, true, true]), issue_2.comments.first.body

      assert_equal build_text([issue_1, issue_2, issue_1, issue_2], [false, false, true, true]), issue_3.body
      assert_equal build_text([issue_1, issue_2, issue_1, issue_2], [false, false, true, true]), issue_3.comments.first.body

      assert_equal 2, issue_1.references.size
      assert_equal 2, issue_2.references.size
      assert_equal 2, issue_3.references.size

      assert_equal issue_1_ref_times, issue_1.references.map(&:created_at).sort
      assert_equal issue_2_ref_times, issue_2.references.map(&:created_at).sort
      assert_equal issue_3_ref_times, issue_3.references.map(&:created_at).sort

      transfer = IssueTransfer.new(old_issue: issue_1, old_repository: issue_1.repository,
        new_repository: @new_repository, actor: @owner)

      transfer.transfer!

      # After 2nd transfer
      issue_1 = @new_repository.issues.find_by(id: T.must(transfer.new_issue).id)
      issue_2.reload
      issue_3.reload

      assert_equal 1, issue_1.events.size
      assert issue_1.events.map(&:event) == ["transferred"]
      assert_equal 1, issue_2.events.size
      assert issue_2.events.map(&:event) == ["transferred"]
      assert_equal 0, issue_3.events.size

      assert_equal build_text([issue_2, issue_3, issue_2, issue_3], [false, false, true, true]), issue_1.body
      assert_equal build_text([issue_2, issue_3, issue_2, issue_3], [false, false, true, true]), issue_1.comments.first.body

      assert_equal build_text([issue_1, issue_3, issue_1, issue_3], [false, false, true, true]), issue_2.body
      assert_equal build_text([issue_1, issue_3, issue_1, issue_3], [false, false, true, true]), issue_2.comments.first.body

      assert_equal build_text([issue_1, issue_2, issue_1, issue_2], [false, false, true, true]), issue_3.body
      assert_equal build_text([issue_1, issue_2, issue_1, issue_2], [false, false, true, true]), issue_3.comments.first.body

      assert_equal 2, issue_1.references.size
      assert_equal 2, issue_2.references.size
      assert_equal 2, issue_3.references.size

      assert_equal issue_1_ref_times, issue_1.references.map(&:created_at).sort
      assert_equal issue_2_ref_times, issue_2.references.map(&:created_at).sort
      assert_equal issue_3_ref_times, issue_3.references.map(&:created_at).sort

      transfer = IssueTransfer.new(old_issue: issue_3, old_repository: issue_3.repository,
        new_repository: @new_repository, actor: @owner)

      transfer.transfer!

      # After 3rd transfer
      issue_1.reload
      issue_2.reload
      issue_3 = @new_repository.issues.find_by(id: T.must(transfer.new_issue).id)

      assert_equal 1, issue_1.events.size
      assert issue_1.events.map(&:event) == ["transferred"]
      assert_equal 1, issue_2.events.size
      assert issue_2.events.map(&:event) == ["transferred"]
      assert_equal 1, issue_3.events.size
      assert issue_2.events.map(&:event) == ["transferred"]

      assert_equal build_text([issue_2, issue_3, issue_2, issue_3], [false, false, true, true]), issue_1.body
      assert_equal build_text([issue_2, issue_3, issue_2, issue_3], [false, false, true, true]), issue_1.comments.first.body

      assert_equal build_text([issue_1, issue_3, issue_1, issue_3], [false, false, true, true]), issue_2.body
      assert_equal build_text([issue_1, issue_3, issue_1, issue_3], [false, false, true, true]), issue_2.comments.first.body

      assert_equal build_text([issue_1, issue_2, issue_1, issue_2], [false, false, true, true]), issue_3.body
      assert_equal build_text([issue_1, issue_2, issue_1, issue_2], [false, false, true, true]), issue_3.comments.first.body

      assert_equal 2, issue_1.references.size
      assert_equal 2, issue_2.references.size
      assert_equal 2, issue_3.references.size

      assert_equal issue_1_ref_times, issue_1.references.map(&:created_at).sort
      assert_equal issue_2_ref_times, issue_2.references.map(&:created_at).sort
      assert_equal issue_3_ref_times, issue_3.references.map(&:created_at).sort
    end

    test "transfers all of an issue's project cards" do
      user_project = create(:project, owner: @owner)
      user_card = create(:pending_project_card, content: @issue, project: user_project)
      assert_equal 1, user_project.cards.count

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository,
                                   new_repository: @new_repository, actor: @owner)
      transfer.transfer!

      user_project.reload
      assert_equal 1, user_project.cards.count
      assert_equal transfer.new_issue, user_project.cards.first.content
    end

    test "transfers all of an issue's memex_project_items when issue is owned by the memex's org" do
      memex = create(:memex_project, owner: @org)
      memex_item = create(:memex_project_item, content: @issue, memex_project: memex)
      assert_equal 1, memex.memex_project_items.count

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository,
                                   new_repository: @new_repository, actor: @owner)
      transfer.transfer!

      memex.reload
      assert_equal 1, memex.memex_project_items.count
      assert_equal transfer.new_issue, memex.memex_project_items.first.content
      assert_equal transfer.new_repository, memex.memex_project_items.first.repository
    end

    test "transfers issue when project item is archived and owned by the memex's org" do
      memex = create(:memex_project, owner: @org)

      memex_item = create(:memex_project_item, content: @issue, memex_project: memex)
      memex_item.archive!

      assert_equal 1, memex.memex_project_items.count

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository,
                                   new_repository: @new_repository, actor: @owner)
      transfer.transfer!

      memex.reload
      assert_equal 1, memex.memex_project_items.count
      assert_equal transfer.new_issue, memex.memex_project_items.first.content
      assert_equal transfer.new_repository, memex.memex_project_items.first.repository
    end

    test "deletes the issue from a memex when the memex is owned by a different org" do
      memex = create(:memex_project)
      memex_item = create(:memex_project_item, content: @issue, memex_project: memex)
      assert_equal 1, memex.memex_project_items.count

      refute_equal memex.owner, @issue.repository.owner

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository,
                                   new_repository: @new_repository, actor: @owner)

      perform_enqueued_jobs(only: DestroyDependentRecordsJob) { transfer.transfer! }

      memex.reload
      assert_equal 0, memex.memex_project_items.count
      assert_equal 0, T.must(transfer.new_issue).memex_project_items.count
    end

    test "deletes the issue from a memex when archived and the memex is owned by a different org" do
      memex = create(:memex_project)

      memex_item = create(:memex_project_item, content: @issue, memex_project: memex)
      memex_item.archive!

      assert_equal 1, memex.memex_project_items.count

      refute_equal memex.owner, @issue.repository.owner

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository,
                                   new_repository: @new_repository, actor: @owner)

      perform_enqueued_jobs(only: DestroyDependentRecordsJob) { transfer.transfer! }

      memex.reload
      assert_equal 0, memex.memex_project_items.count
      assert_equal 0, T.must(transfer.new_issue).memex_project_items.count
    end

    test "deletes a cards for repo projects from the issue" do
      repo_project = create(:project, owner: @issue.repository)
      repo_card = create(:pending_project_card, content: @issue, project: repo_project)
      assert_equal 1, repo_project.cards.count

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository,
                                   new_repository: @new_repository, actor: @owner)
      transfer.transfer!
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob])

      repo_project.reload
      assert_empty repo_project.cards
    end

    test "transfers an issue's sub-issues and calculates sub-issue list" do
      child1 = create(:issue, title: "child 1", repository: @old_repository)
      child2 = create(:issue, title: "child 2", repository: @old_repository)
      child3 = create(:issue, title: "child 3", repository: @old_repository, state: "closed")

      @issue.add_sub_issue!(child1, @owner.id)
      @issue.add_sub_issue!(child2, @owner.id)
      @issue.add_sub_issue!(child3, @owner.id)

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository,
        new_repository: @new_repository, actor: @owner)
      transfer.transfer!

      new_issue = T.must(transfer.new_issue).reload
      assert_equal [child1, child2, child3], new_issue.prioritized_sub_issues
      assert new_issue.sub_issue_list.total == 3
      assert new_issue.sub_issue_list.completed == 1
    end

    test "instruments hydro messaging for the new sub-issues" do
      Timecop.freeze do

        child1 = create(:issue, title: "child 1", repository: @old_repository)
        child2 = create(:issue, title: "child 2", repository: @old_repository)
        child3 = create(:issue, title: "child 3", repository: @old_repository, state: "closed")

        @issue.add_sub_issue!(child1, @owner.id)
        @issue.add_sub_issue!(child2, @owner.id)
        @issue.add_sub_issue!(child3, @owner.id)

        transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository,
          new_repository: @new_repository, actor: @owner)

        reset_hydro
        transfer.transfer!

        assert_hydro_messages(count: 3, schema: "github.v1.SubIssueAdd")
        [child1, child2, child3].each do |sub_issue|
          assert_hydro_published({
            actor: Hydro::EntitySerializer.user(@owner),
            source_issue_repository: Hydro::EntitySerializer.repository(@new_repository),
            source_issue: Hydro::EntitySerializer.issue(T.must(transfer.new_issue)),
            target_issue: Hydro::EntitySerializer.issue(sub_issue),
            existing: true,
            transfer: true,
          }, schema: "github.v1.SubIssueAdd")
        end
      end
    end

    test "notifies graphql subscription channel for newly created sub-issues" do
      frozen_now = Time.utc(2024, 7, 16, 21, 16, 9).freeze
      child1 = create(:issue, title: "child 1", repository: @old_repository)
      child2 = create(:issue, title: "child 2", repository: @old_repository)
      child3 = create(:issue, title: "child 3", repository: @old_repository, state: "closed")

      @issue.add_sub_issue!(child1, @owner.id)
      @issue.add_sub_issue!(child2, @owner.id)
      @issue.add_sub_issue!(child3, @owner.id)

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository,
        new_repository: @new_repository, actor: @owner)

      transfer.send(:create_copy_issue)
      new_issue = T.must(transfer.new_issue)

      GitHub::WebSocket.stubs(:notify_graphql_subscription_channel)
      GitHub::WebSocket.expects(:notify_graphql_subscription_channel).with(any_parameters)

      Timecop.freeze frozen_now do
        [child1, child2, child3].each do |sub_issue|
          topic = ":issueUpdated:id:#{sub_issue.global_relay_id}"
          channel_name = Platform::Subscription.current_format.generate_channel_name(
            topic:,
            subscription_arguments: { id: sub_issue.global_relay_id }
          )
          GitHub::WebSocket.expects(:notify_graphql_subscription_channel).with(channel_name, {
            scope_object: {
              parent_issue_updated: true
            },
            subscription_topic: topic,
            scope: nil,
            dispatch_time: frozen_now.to_f,
          })
        end

        transfer.transfer!
      end
    end

    test "does not add sub-issues when we exceed an acceptable replication wait time" do
      child1 = create(:issue, title: "child 1", repository: @old_repository)
      @issue.add_sub_issue!(child1, @owner.id)

      WaitForReplication
      .any_instance
      .expects(:wait!)
      .raises(
        WaitForReplication::DataUnavailable.new(store_name: SubIssue.cluster_name, wait_required: 6.0, max_wait: 5.0)
      )

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository,
        new_repository: @new_repository, actor: @owner)
      assert_raises WaitForReplication::DataUnavailable do
        transfer.transfer!
      end

      assert transfer.state == "errored"
      assert_empty T.must(transfer.new_issue).sub_issues
      assert_equal [child1], @issue.sub_issues
    end

    test "does not delete sub-issues from the parent if the sub-issue insert fails" do
      child1 = create(:issue, title: "child 1", repository: @old_repository)
      child2 = create(:issue, title: "child 2", repository: @old_repository)
      child3 = create(:issue, title: "child 3", repository: @old_repository)

      @issue.add_sub_issue!(child1, @owner.id)
      @issue.add_sub_issue!(child2, @owner.id)
      @issue.add_sub_issue!(child3, @owner.id)

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository,
        new_repository: @new_repository, actor: @owner)

      SubIssue.stubs(:insert_all!).raises(ActiveRecord::ConnectionFailed)

      assert_raises ActiveRecord::ConnectionFailed do
        transfer.transfer!
      end

      assert transfer.state == "errored"
      assert @issue.reload

      assert_equal [child1, child2, child3], @issue.prioritized_sub_issues
      assert_equal [], T.must(transfer.new_issue).reload.prioritized_sub_issues
    end

    test "destroys any existing parent issue on the new issue" do
      parent = create(:issue, title: "parent", repository: @old_repository)
      @issue.add_or_replace_parent!(parent, @owner)

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository,
        new_repository: @new_repository, actor: @owner)

      transfer.send(:create_copy_issue)
      new_issue = T.must(transfer.new_issue)

      other_parent = create(:issue, title: "other parent", repository: @old_repository)
      SubIssue.build(
        source_issue_id: other_parent.id,
        source_repository_id: other_parent.repository_id,
        target_issue_id: new_issue.id,
        actor_id: @owner.id,
        priority: 1
      ).save(validate: false)
      old_parent = SubIssue.last

      assert old_parent.target_issue_id == new_issue.id
      assert_equal other_parent, new_issue.reload.parent

      transfer.transfer!

      assert_equal parent, new_issue.reload.parent
      assert_raises(ActiveRecord::RecordNotFound) { old_parent.reload }
    end

    test "transfers an issue's parent reference" do
      parent = create(:issue, title: "parent", repository: @old_repository)

      @issue.add_or_replace_parent!(parent, @owner)
      @issue.reload

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository,
        new_repository: @new_repository, actor: @owner)
      transfer.transfer!

      new_issue = T.must(transfer.new_issue).reload
      assert_equal parent.reload, T.must(new_issue.parent)
    end

    test "instruments hydro messaging for the updated parent" do
      Timecop.freeze do

        parent = create(:issue, title: "parent", repository: @old_repository)

        @issue.add_or_replace_parent!(parent, @owner)
        @issue.reload

        transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository,
          new_repository: @new_repository, actor: @owner)

        reset_hydro
        transfer.transfer!

        assert_hydro_messages(count: 1, schema: "github.v1.SubIssueAdd")
        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(@owner),
          source_issue_repository: Hydro::EntitySerializer.repository(@old_repository),
          source_issue: Hydro::EntitySerializer.issue(parent),
          target_issue: Hydro::EntitySerializer.issue(T.must(transfer.new_issue)),
          existing: true,
          transfer: true,
        }, schema: "github.v1.SubIssueAdd")
      end
    end

    test "notifies graphql subscription channel for parent issue changes" do
      frozen_now = Time.utc(2024, 7, 16, 21, 16, 9).freeze
      parent = create(:issue, title: "parent", repository: @old_repository)

      @issue.add_or_replace_parent!(parent, @owner)
      @issue.reload

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository,
        new_repository: @new_repository, actor: @owner)

      GitHub::WebSocket.stubs(:notify_graphql_subscription_channel)
      GitHub::WebSocket.expects(:notify_graphql_subscription_channel).with(any_parameters)

      Timecop.freeze frozen_now do
        topic = ":issueUpdated:id:#{parent.global_relay_id}"
        channel_name = Platform::Subscription.current_format.generate_channel_name(
          topic:,
          subscription_arguments: { id: parent.global_relay_id }
        )
        GitHub::WebSocket.expects(:notify_graphql_subscription_channel).with(channel_name, {
          scope_object: {
            sub_issues_updated: true
          },
          subscription_topic: topic,
          scope: nil,
          dispatch_time: frozen_now.to_f,
        })

        transfer.transfer!
      end
    end

    test "rolls back the transaction to delete issue parent if the insert fails" do
      parent = create(:issue, title: "parent", repository: @old_repository)
      @issue.add_or_replace_parent!(parent, @owner)
      @issue.reload

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository,
        new_repository: @new_repository, actor: @owner)

      SubIssue.stubs(:insert!).raises(ActiveRecord::ConnectionFailed)

      assert_raises ActiveRecord::ConnectionFailed do
        transfer.transfer!
      end

      assert transfer.state == "errored"
      assert @issue.reload

      assert_equal parent, @issue.parent
      refute T.must(transfer.new_issue).parent
    end

    test "does not make excessive queries to sub-issues table" do
      child1 = create(:issue, title: "child 1", repository: @old_repository)
      child2 = create(:issue, title: "child 2", repository: @old_repository)
      child3 = create(:issue, title: "child 3", repository: @old_repository)

      @issue.add_sub_issue!(child1, @owner.id)
      @issue.add_sub_issue!(child2, @owner.id)
      @issue.add_sub_issue!(child3, @owner.id)

      parent = create(:issue, title: "parent", repository: @old_repository)
      @issue.add_or_replace_parent!(parent, @owner)
      @issue.reload

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository,
        new_repository: @new_repository, actor: @owner)

      # 4 select (2 for sub-issues, 1 for parent, 1 for destroy_dependents_in_background on issue delete)
      # 2 delete (1 for sub-issues, 1 for parent)
      # 2 insert (1 for sub-issues, 1 for parent)
      # 2 select for instrumentation (1 for sub-issues, 1 for parent)
      # 2 (update_list_heights_on_destroy)
      # 5 to check if parent is valid
      # 1 to reload parent association for instrumentation
      assert_max_query_count_per_table({ sub_issues: 18 }) do
        transfer.transfer!
      end
    end

    context "transfers that were in progress when this change was deployed" do
      context "old and new issue created_at don't match" do
        test "updates created_at" do
          transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
          transfer.send(:create_copy_issue)
          @issue.update_columns(created_at: 1.week.ago)
          new_issue = transfer.new_issue

          assert_changes -> { T.must(new_issue).created_at }, to: @issue.created_at do
            transfer.complete_transfer
          end
        end
      end

      context "old and new issue created_at match" do
        test "does not update created_at" do
          @issue.update_columns(created_at: 1.week.ago)
          transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
          transfer.send(:create_copy_issue)
          new_issue = transfer.new_issue

          assert_no_changes -> { T.must(new_issue).created_at } do
            transfer.complete_transfer
          end
        end
      end
    end

    test "transfers assignees" do
      @issue.add_assignees(@owner)
      @issue.save!
      assignment = @issue.assignments[0]
      assert_equal 1, @issue.events.where(event: "assigned").size
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)

      pre_transfer_update_count = hydro_message_count(schema: "github.v1.IssueUpdate")
      perform_enqueued_jobs(only: @all_notification_jobs) do
        transfer.transfer!
      end

      new_issue = T.must(transfer.new_issue).reload
      assert_equal [@owner], T.must(transfer.new_issue).assignees.reload
      assert_equal 1, new_issue.events.where(event: "assigned").size
      assert_equal @issue.assignees[0].created_at, new_issue.assignees[0].created_at
      assert_equal new_issue.repository.id, new_issue.assignments[0].repository_id
      assert_empty Assignment.where(id: assignment.id)
      assert_expected_notifications(pre_transfer_update_count)
    end

    test "skips collaborator validation when transferring assignees" do
      collaborator = create(:user, login: "collab")
      @org.add_member(collaborator, action: :write)
      @issue.add_assignees(collaborator)
      @issue.save!
      assert_equal 1, @issue.events.where(event: "assigned").size

      @org.remove_member_without_callbacks_and_notifications(collaborator, background: false)
      @org.reload
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)

      perform_enqueued_jobs(only: @all_notification_jobs) do
        transfer.transfer!
      end

      new_issue = T.must(transfer.new_issue).reload
      assert_equal [collaborator], T.must(transfer.new_issue).assignees.reload
      assert_equal 1, new_issue.events.where(event: "assigned").size
    end

    test "assignment transfer copies only new assignments" do
      @issue.add_assignees(@owner)
      @issue.save!
      assert_equal 1, @issue.events.where(event: "assigned").size
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)

      transfer.send(:create_copy_issue)
      new_issue = T.must(transfer.new_issue).reload
      assert_equal [], new_issue.assignees
      Assignment.create(
        assignee: @owner,
        issue: new_issue,
        created_at: @issue.assignments[0].created_at,
        skip_trigger_assigned_event: true)

      # expecting no assignments as the we manually created the single assignment
      copied_assignments = transfer.send(:transfer_assignments)
      assert_empty copied_assignments

      @issue.add_assignees(@member)
      @issue.save!
      copied_assignments = transfer.send(:transfer_assignments)

      # expecting only the new assignment to be copied over
      assert_equal 1, copied_assignments.size
      assert_equal @member.id, copied_assignments[0].assignee_id
    end

    test "transfers subscribers" do
      only = [Newsies::CopyThreadSubscribersJob]

      perform_enqueued_jobs(only: only) do
        create :issue_comment, :wait_for_orchestration, user: @member2, issue: @issue
        @issue.subscribe(@noncollab, :manual)
      end

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)

      perform_enqueued_jobs(only: Newsies::CopyThreadSubscribersJob) do
        transfer.transfer!
      end

      status1 = GitHub.newsies.subscription_status(@member, @new_repository, transfer.new_issue).value
      status2 = GitHub.newsies.subscription_status(@member2, @new_repository, transfer.new_issue).value
      status3 = GitHub.newsies.subscription_status(@noncollab, @new_repository, transfer.new_issue).value

      assert status1.subscribed?
      assert status2.subscribed?
      assert status3.subscribed?

      assert_equal "author", status1.reason
      assert_equal "comment", status2.reason
      assert_equal "manual", status3.reason
    end

    test "do not transfer unsubscribed subscribers" do
      only = [NotifySubscriptionStatusChangeJob, SubscribeAndNotifyJob]

      perform_enqueued_jobs(only: only) do
        @issue.subscribe(@member2, :comment)
        @issue.unsubscribe(@member2)
      end

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)

      perform_enqueued_jobs(only: only) do
        transfer.transfer!
      end

      status1 = GitHub.newsies.subscription_status(@member, @new_repository, transfer.new_issue).value
      status2 = GitHub.newsies.subscription_status(@member2, @new_repository, transfer.new_issue).value

      assert status1.subscribed?
      refute status2.subscribed?

      assert_equal "author", status1.reason
    end

    test "transfers closed state reason" do
      @issue.update_columns(state_reason: "not_planned", state: "closed", closed_at: 1.day.ago, created_at: 1.week.ago)
      create(:issue_event, event: "closed", issue: @issue, state_reason: "not_planned")

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!
      new_issue = T.must(transfer.new_issue)

      assert_equal @issue.events.size, 1

      old_closed_event = @issue.events.first
      new_closed_event = T.must(new_issue).events.where(event: "closed").first

      assert_equal old_closed_event.state_reason, T.must(new_closed_event).state_reason
      assert_equal @issue.state, T.must(new_issue).state
      assert_equal @issue.state_reason, T.must(new_issue).state_reason
    end

    test "transfers reactions" do
      reaction = Reaction.react(user: @owner, subject_id: @issue.id, subject_type: "Issue", content: "tada")
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!

      new_issue_reaction = T.must(IssueReaction.find_by(issue_id: T.must(transfer.new_issue).id, repository_id: transfer.new_repository_id))
      assert_equal reaction.attributes.except("id", "issue_id", "repository_id", "created_at", "updated_at"),
                   new_issue_reaction.attributes.except("id", "issue_id", "repository_id", "created_at", "updated_at")
      assert_in_delta reaction.created_at.to_f, new_issue_reaction.created_at.to_f, 1.second
      assert_in_delta reaction.updated_at.to_f, new_issue_reaction.updated_at.to_f, 1.second
      assert_equal @issue.repository.id, reaction.repository_id
      assert_equal T.must(transfer.new_issue).repository_id, new_issue_reaction.repository_id
      assert_equal T.must(transfer.new_issue).repository, new_issue_reaction.repository

      old_count = IssueReaction.where(issue_id: transfer.old_issue_id, repository_id: transfer.old_repository_id).count
      new_count = IssueReaction.where(issue_id: transfer.new_issue_id, repository_id: transfer.new_repository_id).count
      assert_equal old_count, new_count
    end

    test "reparents issue events" do
      @issue.title = "New transfer me"
      @issue.save!
      issue_2 = create(:issue, repository: @old_repository)
      dupe_event = create(:issue_event, actor: @owner, event: "marked_as_duplicate", issue: @issue, subject: issue_2)

      assert issue_event = @issue.events.find_by(event: "renamed")

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      pre_transfer_update_count = hydro_message_count(schema: "github.v1.IssueUpdate")
      perform_enqueued_jobs(only: @all_notification_jobs) do
        transfer.transfer!
      end

      new_issue = @new_repository.issues.find_by(title: @issue.title)
      new_event = new_issue.events.find_by(event: "renamed")
      new_dupe_event = new_issue.events.find_by(event: "marked_as_duplicate")

      assert_equal new_event.event, issue_event.event
      assert_equal new_event.issue_id, new_issue.id
      assert_equal new_event.created_at, issue_event.created_at
      assert_equal @new_repository, new_issue.repository
      assert_equal dupe_event.subject_id, new_dupe_event.subject_id
      assert_equal dupe_event.subject_type, new_dupe_event.subject_type
      assert_expected_notifications(pre_transfer_update_count)
    end

    test "reparents issue events with deleted user mention" do
      @issue.save!
      user = create(:user, login: "demo")
      @org.add_member(user, action: :admin)
      @issue.body = "Hey @demo, this is a test"
      create(:issue_event, event: "mentioned", issue: @issue, actor: user)
      @issue.save!

      refute_nil @issue.events.reload[0].actor
      user.delete

      assert_nil @issue.events.reload[0].actor
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      pre_transfer_update_count = hydro_message_count(schema: "github.v1.IssueUpdate")
      perform_enqueued_jobs(only: @all_notification_jobs) do
        transfer.transfer!
      end

      new_issue = @new_repository.issues.find_by(title: @issue.title)
      assert_equal @new_repository, new_issue.repository
      assert_expected_notifications(pre_transfer_update_count)
    end

    test "reparents issue events by copy" do
      @issue.title = "New transfer me"
      @issue.save!
      assert issue_event = @issue.events.find_by(event: "renamed")
      event_details_id = issue_event.issue_event_detail.id
      assert event_details_id

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      pre_transfer_update_count = hydro_message_count(schema: "github.v1.IssueUpdate")
      jobs = @all_notification_jobs + [DestroyDependentRecordsJob]
      perform_enqueued_jobs(only: jobs) do
        transfer.transfer!
      end

      new_issue = @new_repository.issues.find_by(title: @issue.title)
      assert new_event = new_issue.events.first
      refute_equal new_event.id, issue_event.id
      assert_equal new_event.created_at, issue_event.created_at
      assert_equal @new_repository, new_event.repository
      assert_equal @new_repository.id, new_event.issue_event_detail.repository_id
      assert_expected_notifications(pre_transfer_update_count)

      # test deletion
      assert_equal 0, IssueEvent.where(issue_id: @issue.id).size
      assert_equal 0, IssueEventDetail.where(id: event_details_id).size
      assert_equal 0, IssueEventDetail.where(issue_event_id: issue_event.id).size
    end

    test "does not fire redundant callbacks when reparenting issue events" do
      @issue.title = "New transfer me"
      @issue.save!

      # We do create a true new "transferred" event for the issue being
      # transferred. That should be the only invocation of these callbacks.
      # Note: It'd be better if we could remove the expectation on number of
      # invocations and instead test that they don't get called with our copied
      # instances, but I'm not sure how to do that. We don't have arguments to
      # test against.
      [
        :update_summary_state,
        :instrument_event,
        :instrument_event_for_hydro,
        :subscribe_and_notify
      ].each do |callback|
        IssueEvent.any_instance.expects(callback).once
      end

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!
    end

    block_list = IssueTransfer::ISSUE_EVENT_BLOCKLIST

    block_list.each do |type|
      test "skips reparenting '#{type}' issue events" do
        event = create(:issue_event, issue: @issue)
        event.update_column(:event, type)

        transfer = IssueTransfer.new(
          old_issue: @issue,
          old_repository: @issue.repository,
          new_repository: @new_repository,
          actor: @owner,
        )
        transfer.transfer!
        refute T.must(transfer.new_issue).events.find_by(event: type)
      end
    end

    test "event types are correctly blocklisted" do
      # ensure that all IssueEvent types are either explicitly blocked from
      # being transferred, or deemed transferrable and added to TRANSFERRABLE_EVENTS

      # Pull Requests are not transferrable, so we ignore PULL_REQUEST_EVENTS

      exempted_events = IssueEvent::VALID_EVENTS - IssueEvent::PULL_REQUEST_EVENTS - TRANSFERRABLE_EVENTS - IssueTransfer::ISSUE_EVENT_BLOCKLIST
      assert_empty exempted_events, "IssueEvent event type(s) #{exempted_events} must be " \
                                    "classified as transferrable or blocked. " \
                                    "Please see #{__FILE__} for more details."

      duplicated_events = TRANSFERRABLE_EVENTS & IssueTransfer::ISSUE_EVENT_BLOCKLIST
      assert_empty duplicated_events, "IssueEvent event type(s) #{duplicated_events} are present in both " \
                                      "TRANSFERRABLE_EVENTS and ISSUE_EVENT_BLOCKLIST. " \
                                      "Please choose one. See #{__FILE__} for more details."
    end

    test "skip copied events" do
      @issue.title = "New transfer me"
      @issue.save!
      assert issue_event = @issue.events.find_by(event: "renamed")

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
      transfer.save!

      new_issue = T.must(transfer.new_issue)
      assert_equal 0, new_issue.events.reload.size
      transfer.send(:transfer_events_and_labels)

      assert_equal 1, new_issue.events.reload.size
      ids = new_issue.events.map(&:id)

      transfer.send(:transfer_events_and_labels)
      assert_equal 1, new_issue.events.reload.size
      assert_equal ids, new_issue.events.map(&:id)
      assert_equal 1, IssueEventDetail.where(issue_event_id: new_issue.events[0].id).size
    end

    test "reparents issues edits by copy" do
      @issue.update_body("Foo edit", @owner)
      old_edits = @issue.user_content_edits
      old_edits_count = old_edits.count
      assert old_edits_count > 0

      # add a user_content_edit entry to validate this works as well.
      old_edits.each do |old_edit|
        user_content_edit = UserContentEdit.create!(
          user_content_id: @issue.id,
          user_content_type: "issue",
          edited_at: Time.now.utc,
          editor_id: @owner.id
        )

        old_edit.user_content_edit_id = user_content_edit.id
        old_edit.save!
      end

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!

      new_issue = @new_repository.issues.find_by(title: @issue.title)
      new_edits = new_issue.user_content_edits
      assert_equal new_edits.count, old_edits_count

      transfer_key = -> (record) { [record.editor_id, record.created_at, record.compressed_diff] }
      all_records_copied = old_edits.all? do |old_edit|
        new_edits.find do |new_edit|
          transfer_key.call(new_edit) == transfer_key.call(old_edit)
        end
      end
      assert all_records_copied
    end

    test "reparents comments" do
      issue_comment = @issue.comments.create!(user: @owner, body: "Cool")

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!

      issue_comment = T.must(transfer.new_issue).reload.comments.last
      new_issue = @new_repository.issues.find_by(title: @issue.title)
      assert_equal new_issue, issue_comment.issue
      assert_equal @new_repository, issue_comment.repository
      assert_equal issue_comment.body, issue_comment.compressed_body
    end

    test "reparents comments by copying" do
      issue_comment = @issue.comments.create!(user: @owner, body: "Cool")

      # We're suppressing many of the callbacks. Assert that none of the below
      # should be getting called.
      [
        :subscribe_to_issue,
        :update_issue_comments_count,
        :instrument_creation,
        :subscribe_and_notify
      ].each do |callback|
        IssueComment.any_instance.expects(callback).never
      end

      # Expected once when we validate old comment
      IssueComment.any_instance.expects(:validate_comment_is_authorized).once
      IssueComment.any_instance.expects(:ensure_creator_is_not_blocked).once

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!

      new_issue = @new_repository.issues.find_by(title: @issue.title)
      new_comment = new_issue.comments.first
      assert_equal issue_comment.user.id, new_comment.user.id
      assert_equal issue_comment.created_at, new_comment.created_at
      assert_equal issue_comment.body, new_comment.compressed_body
      assert_equal new_issue.comments.count, new_issue.issue_comments_count
      assert_expected_notifications
    end

    test "comments transfer by copying handles empty comments" do
      issue_comment = @issue.comments.create!(user: @owner, body: "ak")
      assert issue_comment.valid?

      issue_comment.update_attribute("body", "")
      refute issue_comment.reload.valid?

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!

      new_issue = @new_repository.issues.find_by(title: @issue.title)
      refute new_issue.comments.any?
      assert_expected_notifications(0, 1) # one comment update expected
    end

    test "reparents comment edits by copy" do
      issue_comment = create(:issue_comment, :wait_for_orchestration, :with_edit, issue: @issue, user: @owner, body: "Cool")
      old_edits = issue_comment.user_content_edits
      old_edits_count = old_edits.count
      assert old_edits_count > 0

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!

      new_issue = @new_repository.issues.find_by(title: @issue.title)
      new_comment = new_issue.comments.first
      new_edits = new_comment.user_content_edits
      assert_equal new_edits.count, old_edits_count

      transfer_key = -> (record) { [record.editor_id, record.created_at, record.compressed_diff] }
      all_records_copied = old_edits.all? do |old_edit|
        new_edits.find do |new_edit|
          transfer_key.call(new_edit) == transfer_key.call(old_edit)
        end
      end
      assert all_records_copied
    end

    test "reparents comment edits by copy even if the comment edit has a legacy user_content_edit_id value" do
      issue_comment = create(:issue_comment, :wait_for_orchestration, :with_edit, issue: @issue, user: @owner, body: "Cool")
      old_edits = issue_comment.user_content_edits
      old_edits.first.user_content_edit_id = 1
      old_edits.first.save
      old_edits_count = old_edits.count
      assert old_edits_count > 0

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!

      new_issue = @new_repository.issues.find_by(title: @issue.title)
      new_comment = new_issue.comments.first
      new_edits = new_comment.user_content_edits
      assert_equal new_edits.count, old_edits_count

      transfer_key = -> (record) { [record.editor_id, record.created_at, record.compressed_diff] }
      all_records_copied = old_edits.all? do |old_edit|
        new_edits.find do |new_edit|
          transfer_key.call(new_edit) == transfer_key.call(old_edit)
        end
      end
      assert all_records_copied
    end

    test "reparents comment attachments" do
      GitHub.user_images_cdn_url = "https://user-images-cdn.githubusercontent.com/"
      GitHub.s3_uploads_enabled = true
      asset = save_file_for_uploadable(UserAsset.new(uploader: @owner))
      issue_comment = create(:issue_comment, :wait_for_orchestration, issue: @issue, user: @owner, body: "yo ![](#{asset.storage_external_url}) ![](foo.jpg)")

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!

      new_issue = @new_repository.issues.find_by(title: @issue.title)
      assert_equal Attachment.count, 1
      assert_equal new_issue.comments.first.attachments.first, Attachment.first
      assert issue_comment.attachments.empty?
    end

    test "transfers comment reactions with copy" do
      issue_comment = create(:issue_comment, issue: @issue, user: @owner, body: "Body")
      reaction = issue_comment.react(actor: @owner, content: "tada")
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!

      new_comment = T.must(transfer.new_issue).reload.comments.first
      copied_reaction = T.must(IssueCommentReaction.find_by(issue_comment_id: new_comment.id))

      assert_equal reaction.user_id, copied_reaction.user_id
      assert_equal reaction.content, copied_reaction.content
      assert_in_delta reaction.created_at.to_f, copied_reaction.created_at.to_f, 1.second

      # The factory has 0, while the copied_reaction has false. They are
      # functionally equivalent (as provided by the Spammable module), so we
      # just want to assert they have one or the other.
      assert [0, false].include? reaction[:user_hidden]
      assert [0, false].include? copied_reaction[:user_hidden]

      old_count = issue_comment.reactions.count
      new_count = new_comment.reactions.count
      assert_equal old_count, new_count

      assert_equal copied_reaction.repository_id, @new_repository.id
    end

    test "preloads comment associations before transferring with copy" do
      GitHub.user_images_cdn_url = "https://user-images-cdn.githubusercontent.com/"
      GitHub.s3_uploads_enabled = true
      asset = save_file_for_uploadable(UserAsset.new(uploader: @owner))
      issue_comment = create(:issue_comment, :wait_for_orchestration, :with_edit, issue: @issue, user: @owner, body: "yo ![](#{asset.storage_external_url})")
      issue_comment.react(actor: @owner, content: "tada")
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)

      query_counts = {
        # With preloading, there should be 1 query for old issue comments and
        # 1 for new. There is also a platform loader query "latest user content
        #   edit" that I'm not sure about. There are also 2 INSERT queries
        issue_comment_edits: 5,
        # With preloading, there should be 3 reactions queries for issue
        # reactions, and 2 for issue comment reactions (1 each for old and new
        # reactions)
        reactions: 6,
        # There should be 2 SELECT queries for issue_comment_reactions (1 each for old and new)
        # plus 1 INSERT
        issue_comment_reactions: 3,
        # One attachment query for the issue and one for the comment. Plus one
        # other showing up in CI?
        # plus 1 UPDATE
        attachments: 4,
      }
      assert_max_query_count_per_table(query_counts, backtrace_lines: 15) do
        transfer.transfer!
      end
    end

    test "updates comment content references on copy" do
      test_url = "https://github-integration.atlassian.net/test"
      issue_comment = create(:issue_comment, :wait_for_orchestration, issue: @issue, user: @owner, body: test_url)
      ContentReference.create!(reference: test_url, content: issue_comment, user: @owner)
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!
      refute ContentReference.where(content_id: T.must(transfer.new_issue).reload.comments.first.id).empty?
    end

    test "transfers subscriptions comment authors when copying" do
      user = create(:user)
      create(:issue_comment, :wait_for_orchestration, issue: @issue, user: user, body: "Test")
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)

      only = [Newsies::CopyThreadSubscribersJob]
      perform_enqueued_jobs(only: only) do
        transfer.transfer!
        issue_id = T.must(transfer.new_issue).id
        assert Newsies::ThreadSubscription.find_by({ reason: "comment", user_id: user.id, thread_key: "Issue;#{issue_id}" })
      end
    end

    test "creates an issue event on the new issue" do
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!

      new_issue = @new_repository.issues.find_by(title: @issue.title)
      refute_nil new_issue.events.find_by(event: "transferred")
    end

    test "allows issue to be transferred even if author was blocked" do
      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        @org.remove_member(@member)
      end
      @org.block(@member)
      assert @member.blocked_by?(@org), "Member should be blocked from org"

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!

      assert_equal @issue.user, T.must(transfer.new_issue).user
    end

    test "allows issue to be transferred when authored by a bot" do
      bot = create(:bot)
      old_issue = create(:issue, user: bot, repository: @old_repository)

      transfer = IssueTransfer.new(old_issue: old_issue, old_repository: @old_repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!

      assert_equal bot, T.must(transfer.new_issue).user
    end

    test "converts bare issue references in body to global issue references" do
      referenced_issue = create :issue, title: "I'm staying put", user: @member, repository: @old_repository
      @issue.update!(body: "This is related to ##{referenced_issue.number}")

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!

      new_issue = @new_repository.issues.find_by(title: @issue.title)
      assert_equal "This is related to #{[@old_repository.name_with_display_owner, "#", referenced_issue.number].join}", new_issue.body
    end

    test "converts bare issue references at start of line in body to global issue references" do
      referenced_issue = create :issue, title: "I'm staying put", user: @member, repository: @old_repository
      @issue.update!(body: "##{referenced_issue.number}")

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!

      new_issue = @new_repository.issues.find_by(title: @issue.title)
      assert_equal [@old_repository.name_with_display_owner, "#", referenced_issue.number].join, new_issue.body
    end

    test "converts bare issue references in body to global issue references when referenced issue was transferred already" do
      referenced_issue = create :issue, title: "I'm going to be transferred first", user: @member, repository: @old_repository
      @issue.update!(body: "This is related to ##{referenced_issue.number}")

      # first, transfer the referenced issue
      transfer = IssueTransfer.new(old_issue: referenced_issue, old_repository: referenced_issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!
      transferred_issue = T.must(transfer.new_issue)

      # then, transfer the issue that references it
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!

      new_issue = T.must(@new_repository.issues.find_by(title: @issue.title))
      assert_equal "This is related to #{@new_repository.name_with_owner}##{transferred_issue.number}", new_issue.body
    end

    test "converts bare issue references in body to global issue references when referenced issue was transferred already and then got deleted" do
      referenced_issue = create :issue, title: "I'm going to be transferred first", user: @member, repository: @old_repository
      @issue.update!(body: "This is related to ##{referenced_issue.number}")

      # first, transfer the referenced issue
      transfer = IssueTransfer.new(old_issue: referenced_issue, old_repository: referenced_issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!
      transferred_issue = T.must(transfer.new_issue)

      # delete it
      IssueOrchestration.delete_issue(issue: transferred_issue, actor: @member).execute!(synchronous: true)

      # then, transfer the issue that references it
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!

      new_issue = T.must(@new_repository.issues.find_by(title: @issue.title))
      assert_equal "This is related to #{@new_repository.name_with_owner}##{transferred_issue.number}", new_issue.body
    end

    test "converts bare pull_request references in body to global issue references" do
      referenced_issue = create :issue, title: "I'm staying put", user: @member, repository: @old_repository

      example_repo :pull_request_source, @old_repository
      pull =
        create(:pull_request,
          repository:      @old_repository,
          base_repository: @old_repository,
          base_user:       @old_repository.owner,
          base_ref:        "master",
          head_repository: @old_repository,
          head_user:       @issue.user,
          head_ref:        "master-merged-topic",
          issue:           referenced_issue,
          )

      @issue.update!(body: "This is related to ##{pull.number}")

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!

      new_issue = @new_repository.issues.find_by(title: @issue.title)
      assert_equal "This is related to #{[@old_repository.name_with_display_owner, "#", referenced_issue.number].join}", new_issue.body
    end

    test "does not convert bare issue reference if referenced issue does not exist" do
      non_existent_issue_num = @old_repository.issues.maximum(:number) + 1000
      assert_empty @old_repository.issues.where(number: non_existent_issue_num)

      @issue.update!(body: "This is related to ##{non_existent_issue_num}")

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!

      new_issue = @new_repository.issues.find_by(title: @issue.title)
      assert_equal new_issue.body, @issue.body
    end

    test "does not convert global issue references in body" do
      unrelated_repo = create(:repository, owner: @org, created_by_user_id: @owner.id)
      referenced_issue = create :issue, title: "I'm staying put", user: @member, repository: unrelated_repo
      referenced_issue_text = [unrelated_repo.nwo, "#", referenced_issue.number].join
      @issue.update!(body: "This is related to #{referenced_issue_text}")

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!

      new_issue = @new_repository.issues.find_by(title: @issue.title)
      assert_equal new_issue.body, @issue.body
    end

    test "does not convert non-reference text to an issue reference" do
      referenced_issue = create :issue, title: "I'm staying put", user: @member, repository: @old_repository
      # these are not issue references because there is a space or incorrect number of #s
      @issue.update!(body: "This problem has occurred # #{referenced_issue.number} times in production and I have ####{referenced_issue.number} thoughts!")

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!

      new_issue = @new_repository.issues.find_by(title: @issue.title)
      assert_equal new_issue.body, @issue.body
    end

    test "converts bare issue references in comment body to global issue reference" do
      referenced_issue = create :issue, title: "I'm staying put", user: @member, repository: @old_repository
      issue_comment = @issue.comments.create!(user: @owner, body: "Check out ##{referenced_issue.number}")

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!


      issue_comment = T.must(transfer.new_issue).reload.comments.last
      assert_equal "Check out #{[@old_repository.name_with_display_owner, "#", referenced_issue.number].join}", issue_comment.body
    end

    test "does not include suffix in the org name when transferred issue is referenced in another issue" do
      # first issue we are transferring
      referenced_issue = create :issue, title: "I'm moving out", user: @member, repository: @old_repository
      # second issue which stays and in which the first issue is referenced
      staying_issue = create :issue, title: "I'm staying put", user: @member, repository: @old_repository

      # referencing first issue (that will be transferred) in the second one
      issue_comment = staying_issue.comments.create!(user: @owner, body: "Check out ##{referenced_issue.number}")
      referenced_issue.record_reference_from(staying_issue, @owner, Time.now)

      transfer = IssueTransfer.new(old_issue: referenced_issue, old_repository: referenced_issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!
      transfer.save!

      issue_comment.reload

      assert_equal "Check out #{[@new_repository.name_with_display_owner, "#", T.must(transfer.new_issue).number].join}", issue_comment.body
    end

    test "instruments a transfer event" do
      events = subscribe "issue.transfer"

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!
      transfer.save!

      assert transfer.new_issue

      expected_payload = {
        title: @issue.title,
        body: @issue.body,
        org: @old_repository.owner.login,
        org_id: @old_repository.owner.id,
      }

      assert event = events.pop, "expected an instrumentation event"

      assert_equal expected_payload[:org], event.payload[:org]
      assert_equal expected_payload[:org_id], event.payload[:org_id]
    end

    test "does not transfer issue-project events" do
      reopened_event = create(:issue_event, event: "reopened", issue: @issue, actor: @owner)

      untransferrable_events = %w[
        project_v2_item_status_changed
        converted_from_draft
        added_to_project_v2
        removed_from_project_v2
      ]

      untransferrable_events.each do |event|
        create(:issue_event, event: event, issue: @issue, actor: @owner)
      end

      # 1 transferrable event + 4 non-transferrable events
      assert_equal 5, @issue.events.reload.size

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.transfer!
      new_issue = T.must(transfer.new_issue)

      refute_nil new_issue.events.find_by(event: "reopened")
      assert_empty new_issue.events.where(event: untransferrable_events)
    end
  end

  context "#async_transfer!" do
    test "creates new issue to another repository" do
      @issue.update_columns(performed_by_integration_id: 123, state: "closed", closed_at: 1.day.ago, created_at: 1.week.ago)
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.async_transfer!
      new_issue = T.must(transfer.new_issue)

      assert_equal @issue.title, new_issue.title
      assert_equal @issue.user_id, new_issue.user_id
      assert_equal @issue.issue_comments_count, new_issue.issue_comments_count
      assert_equal @issue.state, new_issue.state
      assert_equal @issue.user_hidden, new_issue.user_hidden
      assert_equal @issue.performed_by_integration_id, new_issue.performed_by_integration_id
      assert_equal new_issue.transfer, true
      assert_equal @issue.closed_at, new_issue.closed_at
      assert_equal @issue.created_at, new_issue.created_at
    end

    # This is an integration test that validates the fix for https://github.com/github/search-and-flywheel/issues/392
    test "does not fail when trying to transfer an issue with an old created_at date " do
      @issue.update_columns(created_at: "2007-12-02 00:00:00")
      GitHub.flipper[:tasklist_block_input_validation].enable
      # this number can be anything, as `GitHub::UserContent#low_enough_for_textile`
      # will return `true` as long as the issue responds to this method with a non-null value
      Issue.any_instance.stubs(:max_textile_id).returns(1_000_000)

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.async_transfer!
      new_issue = T.must(transfer.new_issue)

      assert_equal @issue.title, new_issue.title
      assert_equal @issue.created_at, new_issue.created_at
    end

    test "enqueues TransferIssueJob" do
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      assert_enqueued_with(job: TransferIssueJob) do
        transfer.async_transfer!
      end
    end
  end

  context "complete_transfer" do
    test "transfers assignees" do
      @issue.add_assignees(@owner)
      @issue.save!
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
      transfer.save!
      transfer.complete_transfer
      assert_equal [@owner], T.must(transfer.new_issue).assignees.reload
    end

    test "reparents comments" do
      issue_comment = @issue.comments.create!(user: @owner, body: "Cool")

      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
      transfer.save!
      transfer.complete_transfer

      issue_comment = T.must(transfer.new_issue).reload.comments.last
      new_issue = @new_repository.issues.find_by(title: @issue.title)
      assert_equal new_issue, issue_comment.issue
    end

    context "labels" do
      test "does not create new labels in the target repository by default" do
        label = create(:label, repository: @issue.repository, name: "label")
        @issue.add_labels(label)

        transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
        transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
        transfer.save!
        transfer.complete_transfer

        assert_empty T.must(transfer.new_issue).labels.reload
      end

      test "does not transfers label by default if label events don't exist" do
        label = create(:label, repository: @issue.repository, name: "label")
        @issue.labels << label
        @issue.touch
        @issue2.labels << label
        @issue2.touch

        transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
        transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
        transfer.save!
        transfer.complete_transfer

        assert_empty T.must(transfer.new_issue).labels.reload

        transfer = IssueTransfer.new(old_issue: @issue2, old_repository: @issue2.repository, new_repository: @new_repository, actor: @owner)
        transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
        transfer.save!
        transfer.complete_transfer

        new_issue = T.must(transfer.new_issue).reload
        assert_empty new_issue.labels.reload
        assert_equal 0, new_issue.events.to_a.count { |e| e.event == "labeled" }
      end

      test "special emoji labels are transferred as expected" do
        name_1 = "[⭐⭐⭐]aAa" # "[\xE2\xAD\x90\xE2\xAD\x90\xE2\xAD\x90]" + aAa
        name_2 = "[⭐️⭐️⭐️]Aaa" # "[\xE2\xAD\x90\xEF\xB8\x8F\xE2\xAD\x90\xEF\xB8\x8F\xE2\xAD\x90\xEF\xB8\x8F]" + Aaa
        refute_equal name_1, name_2
        label_1 = create(:label, repository: @issue.repository, name: name_1)
        label_2 = create(:label, repository: @new_repository, name: name_2)

        @issue.add_labels(label_1)

        transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
        transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
        transfer.save!
        transfer.complete_transfer

        assert_equal name_2, T.must(transfer.new_issue).labels.reload.first.name
        assert_equal label_2, T.must(transfer.new_issue).labels.reload.first
      end

      test "test label transfer for events with no label in event_details" do
        # Digging into this sentry error: https://sentry.io/organizations/github/issues/2976833113/?project=1885898&query=job%3ATransferIssueJob&statsPeriod=24h
        # This was caused by an issue with "labeled" event that had nil for all label properties in event_details (and no raw_data).
        label = create(:label, repository: @issue.repository, name: "label")
        @issue.add_labels(label)
        label_event = @issue.events.reload[-1]
        label_event.issue_event_detail.update_columns(label_name: nil, label_color: nil, label_id: nil)

        transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
        transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
        transfer.save!
        transfer.complete_transfer

        # since the label is invalid, we don't expect to see a labeled event on the new_issue
        assert_equal "done", transfer.state
        assert_empty T.must(transfer.new_issue).events.select { |e| e.event == "labeled" }
      end

      test "test label transfer for legacy label with raw_body content" do
        source_repo_label = create(:label, repository: @issue.repository, name: "label", color: "d73a4a")
        create(:label, repository: @new_repository, name: "label", color: "d73a4a")
        @issue.add_labels(source_repo_label)
        event = IssueEvent.create!(issue: @issue, actor: @owner, event: "labeled")

        raw_data = {
          label_id: source_repo_label.id,
          label_name: source_repo_label.name,
          label_color: source_repo_label.color,
        }
        encoded = Coders::Handler.new(Coders::IssueEventCoder, compressor: GitHub::ZPack).dump(raw_data)

        # Manually simulate existing production serialized attributes inside
        # the IssueEvent model by inserting raw_data
        # See: https://github.com/github/github/issues/56092
        IssueEvent.where(id: event.id).update_all(raw_data: encoded)

        # Delete the issue_event_details row to simulate pre-transition production
        # where only the serialized attributes from the issue event model exist
        event.issue_event_detail.delete
        event.reload
        event.issue_event_detail.save
        @issue.reload

        assert_equal source_repo_label.id, T.unsafe(event).label_id
        assert_equal source_repo_label.name, T.unsafe(event).label_name
        assert_equal source_repo_label.color, T.unsafe(event).label_color

        transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)

        perform_enqueued_jobs(only: @all_notification_jobs) do
          transfer.transfer!
        end

        new_event = T.must(transfer.new_issue).events.reload[0]
        assert_equal "labeled", new_event.event
        assert_equal source_repo_label.name, new_event.label_name
        assert_equal source_repo_label.color, new_event.label_color
        assert_equal source_repo_label.name, new_event.issue_event_detail.label_name
        assert_equal source_repo_label.color, new_event.issue_event_detail.label_color
        assert_equal @new_repository.id, new_event.issue_event_detail.repository_id
        assert_equal 0, new_event.raw_data.to_h.size
        refute_equal T.unsafe(event).label_id, new_event.label_id
      end

      test "test label transfer for legacy label with raw_body content truncated data case" do
        source_repo_label = create(:label, repository: @issue.repository, name: "label", color: "d73a4a")
        create(:label, repository: @new_repository, name: "label", color: "d73a4a")
        @issue.add_labels(source_repo_label)
        event = IssueEvent.create!(issue: @issue, actor: @owner, event: "labeled")

        raw_data = {
          label_id: source_repo_label.id,
          label_name: source_repo_label.name,
          label_color: source_repo_label.color,
        }
        encoded = Coders::Handler.new(Coders::IssueEventCoder, compressor: GitHub::ZPack).dump(raw_data)

        # Manually simulate existing production serialized attributes inside
        # the IssueEvent model by inserting raw_data
        # See: https://github.com/github/github/issues/56092
        IssueEvent.where(id: event.id).update_all(raw_data: encoded)

        # Update source event's label_id to something wrong to simulate https://github.com/github/issues/issues/1521
        event.issue_event_detail.label_id = "-1"
        event.issue_event_detail.save
        @issue.reload

        transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)

        perform_enqueued_jobs(only: @all_notification_jobs) do
          transfer.transfer!
        end

        new_issue = T.must(transfer.new_issue).reload
        new_event = new_issue.events.reload[0]
        assert_equal "labeled", new_event.event
        assert_equal source_repo_label.name, new_event.label_name
        assert_equal source_repo_label.color, new_event.label_color
        assert_equal source_repo_label.name, new_event.issue_event_detail.label_name
        assert_equal source_repo_label.color, new_event.issue_event_detail.label_color
        assert_equal @new_repository.id, new_event.issue_event_detail.repository_id
        assert_equal 0, new_event.raw_data.to_h.size
        assert_equal new_issue.labels[0].id, new_event.label_id
        refute_equal T.unsafe(event).label_id, new_issue.labels[0].id
        refute_equal -1, new_issue.labels[0].id
        refute_equal T.unsafe(event).label_id, new_event.label_id
      end

      test "uses the existing label in the target repo if label_name matches" do
        source_repo_label = create(:label, repository: @issue.repository, name: "LABEl")
        target_repo_label = create(:label, repository: @new_repository, name: "labeL")
        @issue.add_labels(source_repo_label)

        transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
        transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
        transfer.save!
        transfer.complete_transfer

        assert_equal target_repo_label, T.must(transfer.new_issue).labels.reload.first
      end

      test "issue with partial label events should be able to transter correctly" do
        label_1_name = "label_1"
        label_2_name = "label_2"
        label_3_name = "label_3"

        label_1 = create(:label, repository: @issue.repository, name: label_1_name)
        label_2 = create(:label, repository: @issue.repository, name: label_2_name)
        label_3 = create(:label, repository: @issue.repository, name: label_3_name)

        @issue.add_labels([label_1, label_2, label_3])

        # now, delete the labeled event for label_2, but keep it assigned.
        issue_events = @issue.events.reload
        issue_events.each do |issue_event|
          issue_event.destroy! if issue_event.issue_event_detail.label_id == label_2.id
        end

        assert_equal 2, @issue.events.reload.size

        # now, delete the assignment of label_3, but keep the labeled events.
        issues_labels = IssuesLabels.where(label_id: label_3.id).destroy_all
        @issue.reload

        assert_equal 2, @issue.labels.size

        label_1_new = create(:label, repository: @new_repository, name: label_1_name.upcase)
        label_2_new = create(:label, repository: @new_repository, name: label_2_name.upcase)

        transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
        transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
        transfer.save!
        transfer.complete_transfer

        # label_3 is not created as expected. It is only attached in the events.
        assert_equal 2, @new_repository.labels.size
        assert_same_elements T.must(transfer.new_issue).labels, [label_1_new, label_2_new]
      end

      test "uses the creation data of the old issue for newly created labels in the target repository" do
        label = create(:label, repository: @issue.repository, name: "label")
        @issue.add_labels(label)

        transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
        transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
        transfer.save!
        transfer.complete_transfer(create_labels_if_missing: true)

        assert_equal label.created_at, T.must(transfer.new_issue).labels.reload.first.created_at
      end

      test "sets the color of the existing label in the new repository to the color of the target label" do
        source_repo_label = create(:label, repository: @issue.repository, name: "label", color: "d73a4a")
        target_repo_label = create(:label, repository: @new_repository, name: "label", color: "d72a2a")
        @issue.add_labels(source_repo_label)

        transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
        transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
        transfer.save!
        transfer.complete_transfer

        assert_equal target_repo_label.color, T.must(transfer.new_issue).labels.reload.first.color
      end

      test "labeled events for labels that exist in the target repo refer to the label in the target repo" do
        source_repo_label = create(:label, repository: @issue.repository, name: "label")
        target_repo_label = create(:label, repository: @new_repository, name: "label")
        @issue.add_labels(source_repo_label)

        transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
        transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
        transfer.save!
        transfer.complete_transfer

        new_issue = T.must(transfer.new_issue).reload
        new_issue_label = new_issue.labels.first
        labeled_event = new_issue.events.find { |e| e.event == "labeled" }
        event_detail = labeled_event.issue_event_detail

        assert_equal @new_repository.id, labeled_event.repository_id
        assert_equal target_repo_label.id, event_detail.label_id
        assert_equal target_repo_label.color, event_detail.label_color
        assert_equal target_repo_label.name, event_detail.label_name
      end

      test "unlabeled events for labels that exist in the target repo refer to the label in the target repo" do
        source_repo_label = create(:label, repository: @issue.repository, name: "label")
        target_repo_label = create(:label, repository: @new_repository, name: "label")
        @issue.add_labels(source_repo_label)
        @issue.delete_labels(source_repo_label)

        transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
        transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
        transfer.save!
        transfer.complete_transfer

        new_issue = T.must(transfer.new_issue).reload
        new_issue_label = new_issue.labels.first
        labeled_event = new_issue.events.find { |e| e.event == "unlabeled" }
        event_detail = labeled_event.issue_event_detail

        assert_equal @new_repository.id, labeled_event.repository_id
        assert_equal target_repo_label.id, event_detail.label_id
        assert_equal target_repo_label.color, event_detail.label_color
        assert_equal target_repo_label.name, event_detail.label_name
      end

      test "does not apply the same label twice" do
        label = create(:label, repository: @issue.repository, name: "label")
        create(:label, repository: @new_repository, name: "label")
        @issue.add_labels(label)

        transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
        transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
        transfer.save!

        transfer.send(:transfer_labels, transfer.send(:get_label_mapping))
        transfer.send(:transfer_labels, transfer.send(:get_label_mapping))

        assert_equal 1, T.must(transfer.new_issue).labels.size
      end

      test "handles renamed and deleted labels" do
        old_label_name = "label"
        new_label_name = "new_label"
        label = create(:label, repository: @issue.repository, name: old_label_name)
        deleted_label = create(:label, repository: @issue.repository, name: "delete me")

        # creating the new label in the target repo so not matching properly it will cause a "Validation failed: Name has already been taken" error
        existing_label = create(:label, repository: @new_repository, name: new_label_name)

        @issue.add_labels(label)
        @issue.add_labels(deleted_label)
        label.name = new_label_name
        label.save!

        perform_enqueued_jobs(only: [DestroyIssuesLabelsJob]) { deleted_label.destroy }
        @issue.reload

        transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
        transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
        label_mapping = transfer.send(:get_label_mapping)
        transfer.save!
        transfer.complete_transfer

        new_repo_labels = @new_repository.labels.reload.map { |l| [l.id, l.label_name] }.to_h
        assert_equal new_label_name, label_mapping[label.id].label_name
        assert_nil label_mapping[deleted_label.id] # deleted label is not created in the new repo
        assert_equal 1, T.must(transfer.new_issue).labels.size
        assert_equal new_label_name, T.must(T.must(transfer.new_issue).labels.first).name
      end

      test "instruments an event for Hydro" do
        transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
        transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
        transfer.save!
        transfer.complete_transfer
        assert_hydro_messages(count: 1, schema: "github.v1.IssueTransferred")
      end
    end


    context "assets" do
      test "updates issue body with new asset URL" do
        GitHub.flipper[:secured_images].enable

        original_issue = create(:issue, repository: @old_repository, user: @owner)
        asset = save_file_for_uploadable(UserAsset.new(uploader: @owner, repository: @old_repository))

        original_issue.body = "![](#{asset.storage_external_url})"

        transfer = IssueTransfer.new(old_issue: original_issue, old_repository: @old_repository, new_repository: @new_repository, actor: @owner)
        transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
        transfer.save!
        transfer.complete_transfer

        new_issue = T.must(transfer.new_issue)

        asset.reload
        assert_equal @new_repository.id, asset.repository_id
        assert_equal @new_repository, asset.upload_container
        assert_includes new_issue.body, asset.storage_external_url
      end

      test "updates issue comment body with new asset URL" do
        GitHub.flipper[:secured_images].enable

        original_issue = create(:issue, repository: @old_repository, user: @owner)
        asset = save_file_for_uploadable(UserAsset.new(uploader: @owner, repository: @old_repository))

        issue_comment = original_issue.comments.create!(user: @owner, body: "![](#{asset.storage_external_url})")

        transfer = IssueTransfer.new(old_issue: original_issue, old_repository: @old_repository, new_repository: @new_repository, actor: @owner)
        transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
        transfer.save!
        transfer.complete_transfer

        asset.reload
        assert_equal @new_repository.id, asset.repository_id
        assert_equal @new_repository, asset.upload_container
        assert_includes issue_comment.body, asset.storage_external_url
      end

      context "when user does not have permissions on the assets" do
        test "ignores invalid issue body asset and logs failure, but transfers valid asset" do
          GitHub.flipper[:secured_images].enable

          random_user = create(:user)
          random_repo = create(:repository, owner: random_user)
          random_asset = save_file_for_uploadable(UserAsset.new(uploader: random_user, repository: random_repo))

          valid_asset = save_file_for_uploadable(UserAsset.new(uploader: @owner, repository: @old_repository))

          original_issue = create(:issue, repository: @old_repository, user: @owner)
          original_issue.body = "![](#{random_asset.storage_external_url})\n![](#{valid_asset.storage_external_url})"

          expected_log = {
            "gh.repo.id" => @old_repository.id,
            "gh.issue.id" => original_issue.id,
            "gh.new_repo.id" => @new_repository.id,
            "gh.actor.id" => @owner.id,
            "gh.asset_url" => random_asset.storage_external_url,
          }
          assert_logged(**expected_log) do
            transfer = IssueTransfer.new(old_issue: original_issue, old_repository: @old_repository, new_repository: @new_repository, actor: @owner)
            transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
            transfer.save!
            transfer.complete_transfer
          end

          random_asset.reload
          assert_equal random_repo.id, random_asset.repository_id
          assert_equal random_repo, random_asset.upload_container

          valid_asset.reload
          assert_equal @new_repository.id, valid_asset.repository_id
          assert_equal @new_repository, valid_asset.upload_container
        end

        test "ignores invalid issue comment asset and logs failure, but transfers valid asset" do
          GitHub.flipper[:secured_images].enable

          random_user = create(:user)
          random_repo = create(:repository, owner: random_user)
          random_asset = save_file_for_uploadable(UserAsset.new(uploader: random_user, repository: random_repo))

          valid_asset = save_file_for_uploadable(UserAsset.new(uploader: @owner, repository: @old_repository))

          original_issue = create(:issue, repository: @old_repository, user: @owner)
          issue_comment = original_issue.comments.create!(user: @owner, body: "![](#{random_asset.storage_external_url})\n![](#{valid_asset.storage_external_url})")

          expected_log = {
            "gh.repo.id" => @old_repository.id,
            "gh.issue.id" => original_issue.id,
            "gh.comment.id" => issue_comment.id,
            "gh.new_repo.id" => @new_repository.id,
            "gh.actor.id" => @owner.id,
            "gh.asset_url" => random_asset.storage_external_url,
          }
          assert_logged(**expected_log) do
            transfer = IssueTransfer.new(old_issue: original_issue, old_repository: @old_repository, new_repository: @new_repository, actor: @owner)
            transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
            transfer.save!
            transfer.complete_transfer
          end

          random_asset.reload
          assert_equal random_repo.id, random_asset.repository_id
          assert_equal random_repo, random_asset.upload_container
          assert_includes issue_comment.body, random_asset.storage_external_url

          valid_asset.reload
          assert_equal @new_repository.id, valid_asset.repository_id
          assert_equal @new_repository, valid_asset.upload_container
          assert_includes issue_comment.body, valid_asset.storage_external_url
        end
      end

      test "ignores asset that doesn't belong to origin repo, but transfers valid asset" do
        GitHub.flipper[:secured_images].enable

        other_repo = create(:repository, owner: @owner)
        other_repo_asset = save_file_for_uploadable(UserAsset.new(uploader: @owner, repository: other_repo))

        valid_asset = save_file_for_uploadable(UserAsset.new(uploader: @owner, repository: @old_repository))

        original_issue = create(:issue, repository: @old_repository, user: @owner)
        issue_comment = original_issue.comments.create!(user: @owner, body: "![](#{other_repo_asset.storage_external_url})\n![](#{valid_asset.storage_external_url})")

        transfer = IssueTransfer.new(old_issue: original_issue, old_repository: @old_repository, new_repository: @new_repository, actor: @owner)
        transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
        transfer.save!
        transfer.complete_transfer

        other_repo_asset.reload
        assert_equal other_repo.id, other_repo_asset.repository_id
        assert_equal other_repo, other_repo_asset.upload_container
        assert_includes issue_comment.body, other_repo_asset.storage_external_url

        valid_asset.reload
        assert_equal @new_repository.id, valid_asset.repository_id
        assert_equal @new_repository, valid_asset.upload_container
        assert_includes issue_comment.body, valid_asset.storage_external_url
      end
    end

    context "milestones" do
      test "does not create milestone in the target repository if they don't already exist" do
        due_date = "2022-08-22 00:00:00.000000000 +0000"

        milestone = create(:milestone, repository: @issue.repository, title: "milestone1", due_on: due_date, number: 1)

        @issue.milestone = milestone
        @issue.save!
        @issue.reload

        transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
        transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
        transfer.save!
        transfer.complete_transfer

        assert_nil T.must(transfer.new_issue).milestone

        milestoned_event = T.must(transfer.new_issue).events.find { |e| e.event == "milestoned" }
        assert_nil milestoned_event
      end

      test "gracefully continues if original repository milestone is deleted" do
        due_date = "2022-08-22 00:00:00.000000000 +0000"

        milestone = create(:milestone, repository: @issue.repository, title: "milestone1", due_on: due_date, number: 1)

        @issue.milestone = milestone
        @issue.save!
        @issue.reload

        milestone.destroy

        transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
        transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
        transfer.save!
        transfer.complete_transfer

        assert_nil T.must(transfer.new_issue).milestone

        milestoned_event = T.must(transfer.new_issue).events.find { |e| e.event == "milestoned" }
        assert_nil milestoned_event
      end

      test "create milestone in the target repository if they exist (have the same number and due date)" do
        due_date = "2022-08-22 00:00:00.000000000 +0000"

        milestone = create(:milestone, repository: @issue.repository, title: "milestone1", due_on: due_date, description: "milestone description")
        # create a milestone in the target repo with the same title and due date (but different description)
        milestone_in_new_repo = create(:milestone, repository: @new_repository, title: "milestone1", due_on: due_date, description: "different milestone description")

        @issue.milestone = milestone
        @issue.save!
        @issue.reload

        transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
        transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
        transfer.save!
        transfer.complete_transfer

        new_issue = T.must(transfer.new_issue).reload

        refute_nil new_issue.milestone
        assert_equal @issue.milestone.title, new_issue.milestone.title
        assert_equal @issue.milestone.due_on, new_issue.milestone.due_on
        assert_equal @new_repository.id, new_issue.milestone.repository_id
        assert_equal milestone_in_new_repo.description, new_issue.milestone.description
        assert_equal milestone_in_new_repo.id, new_issue.milestone.id
        milestoned_event = new_issue.events.find { |e| e.event == "milestoned" }
        assert_equal milestone_in_new_repo.id, milestoned_event.milestone_id
        assert_equal 1, new_issue.events.to_a.count { |e| e.event == "milestoned" }
      end

      test "dont create a milestone in the target repo if the title doesn't match" do
        due_date = "2022-08-22 00:00:00.000000000 +0000"

        milestone = create(:milestone, repository: @issue.repository, title: "milestone1", due_on: due_date, description: "milestone description")
        # create a milestone in the target repo with the same due date but different title
        milestone_in_new_repo = create(:milestone, repository: @new_repository, title: "milestone1 b", due_on: due_date, description: "different milestone description")

        @issue.milestone = milestone
        @issue.save!
        @issue.reload

        transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
        transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
        transfer.save!
        transfer.complete_transfer

        new_issue = T.must(transfer.new_issue).reload

        assert_nil new_issue.milestone

        milestoned_event = new_issue.events.find { |e| e.event == "milestoned" }
        assert_nil milestoned_event
      end

      test "dont create a milestone in the target repo if the due date doesn't match" do
        due_date = "2022-08-22 00:00:00.000000000 +0000"
        different_due_date = "2022-08-23 00:00:00.000000000 +0000"
        milestone = create(:milestone, repository: @issue.repository, title: "milestone1", due_on: due_date, description: "milestone description")
        # create a milestone in the target repo with the same title but different due date
        milestone_in_new_repo = create(:milestone, repository: @new_repository, title: "milestone1", due_on: different_due_date, description: "different milestone description")

        @issue.milestone = milestone
        @issue.save!
        @issue.reload

        transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
        transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
        transfer.save!
        transfer.complete_transfer

        new_issue = T.must(transfer.new_issue).reload

        assert_nil new_issue.milestone

        milestoned_event = new_issue.events.find { |e| e.event == "milestoned" }
        assert_nil milestoned_event
      end
    end

    test "creates an issue event on the new issue" do
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
      transfer.save!
      transfer.complete_transfer

      new_issue = @new_repository.issues.find_by(title: @issue.title)
      refute_nil new_issue.events.find_by(event: "transferred")
    end

    test "marks itself as done" do
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
      transfer.save!
      transfer.complete_transfer

      assert_equal "done", transfer.state
    end

    test "destroys the old issue" do
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
      transfer.save!
      transfer.complete_transfer

      transfer.reload
      assert_nil transfer.old_issue
    end

    test "doesn't fail when run again" do
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
      transfer.save!
      transfer.complete_transfer

      transfer.reload
      transfer.complete_transfer
    end

    test "triggers a transfer webhook" do
      event_guid = "be5f4000-b6a0-11ee-8f69-b93ae6629aee"
      SimpleUUID::UUID.any_instance.expects(:to_guid).once.returns(event_guid)
      GitHub.context.push(actor_id: @owner.id)

      event = Hook::Event::IssuesEvent.new action: :transferred, issue_id: @issue.id, actor_id: @owner.id, event_guid: event_guid
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
      transfer.save!

      Hook::Event::IssuesEvent
        .expects(:new)
        .with(issue_id: @issue.id, actor_id: @owner.id, action: :transferred, event_guid: event_guid)
        .returns(event)
      Hook::DeliverySystem.any_instance.expects(:deliver_later)

      transfer.complete_transfer
    end

    test "does not trigger a transfer webhook for a spammy user", skip_enterprise: true do
      spammy_user = create :spammy_user
      repo = create :repository, owner: spammy_user, created_by_user_id: spammy_user.id
      new_repo = create :repository, owner: spammy_user, created_by_user_id: spammy_user.id
      issue = create(:issue, repository: repo, user: spammy_user)

      Hook::DeliverySystem.any_instance.expects(:deliver_later).never

      transfer = IssueTransfer.new(old_issue: issue, old_repository: repo, new_repository: new_repo, actor: spammy_user)
      transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
      transfer.save!
      transfer.complete_transfer
    end
  end

  context "#retry_transfer" do
    test "creates an issue event on the new issue" do
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
      transfer.save!
      transfer.retry_transfer

      new_issue = @new_repository.issues.find_by(title: @issue.title)
      refute_nil new_issue.events.find_by(event: "transferred")
    end

    test "marks itself as done" do
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @owner)
      transfer.send(:create_copy_issue) # This will usually be called by async_transfer! or transfer!
      transfer.save!
      transfer.retry_transfer

      assert_equal "done", transfer.state
    end
  end

  def build_text(issues, full_url, plain = false)
    issues.map.with_index do |i, index| if full_url[index]
                                          "https://github.com/#{i.repository.nwo}/issues/#{i.number}"
                                        else
                                          "#{plain ? "" : i.repository.nwo}##{i.number}"
                                        end
    end.join("\n")
  end

  def assert_expected_notifications(pre_tranfer_issue_update_hydro_events = 0, pre_tranfer_comment_update_hydro_events = 0)
    refute_delivered_any_notifications(@owner)
    GlobalInstrumenter.expects(:instrument).never
    Notifyd::NotifyPublisher.any_instance.expects(:publish).never
    old_repo_hook_actions = @deliveries.all_payloads_for_hook(@old_repo_hook).map { |p| p["action"] }
    new_repo_hook_actions = @deliveries.all_payloads_for_hook(@new_repo_hook).map { |p| p["action"] }
    assert_equal 0, new_repo_hook_actions.count { |a| a == "assigned" }, "expected no assigned notifications"
    assert_equal 0, old_repo_hook_actions.count { |a| a == "assigned" }, "expected no assigned notifications"

    with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
      assert_equal 0, hydro_message_count(schema: "github.v1.IssueCommentUpdate") - pre_tranfer_comment_update_hydro_events, "expected no issue comment update hydro messages"
      assert_equal 0, hydro_message_count(schema: "github.v1.IssueUpdate") - pre_tranfer_issue_update_hydro_events, "expected no issue update hydro messages"
    end
  end

  def create_comment(issue:, body:, user:)
    perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) do
      create(:issue_comment, :wait_for_orchestration, issue:, body:, user:)
    end
  end
end
