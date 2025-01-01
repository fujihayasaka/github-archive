# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueTimelineTest < GitHub::TestCase
  fixtures do
    @owner  = create(:paid_user)
    @repo   = create(:repository, owner: @owner)

    @issue  = create(:issue, repository: @repo, create_references: true)
    @issue2 = create(:issue, repository: @repo, create_references: true)

    @source = create(:repository, owner: @owner, name: "source", from_example: :review_comment_fork)
    @forker = create(:user)
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :review_comment_fork)
    @source.add_member @forker

    @issue_for_pull = create(:issue, user: @forker, repository: @source, create_references: true)
    @pull =
      create(:pull_request,
        repository: @source,
        base_repository: @source,
        base_user: @source.owner,
        base_ref: "master",
        head_repository: @fork,
        head_user: @fork.owner,
        head_ref: "topic",
        issue: @issue_for_pull,
        user: @forker,
      )
    @issue_for_pull.pull_request = @pull

    @memex_project = create(:memex_project, owner: @owner)
  end

  test "issue with empty body and without timeline events" do
    issue = create(:issue, repository: @repo, body: "", create_references: true)

    timeline  = @issue.timeline_for(@owner)

    assert timeline.empty?
  end

  test "issue referencing another issue" do
    issue = perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) do
      create(:issue, repository: @repo, body: "check out ##{@issue.number}", create_references: true)
    end

    timeline  = @issue.timeline_for(@owner)
    ref_items = timeline.collect { |i|  i.source if i.respond_to?(:source) }
    assert_includes ref_items, issue
  end

  test "issue referencing another issue on update" do
    assert_equal [], @issue.timeline_for(@owner)

    perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) { @issue2.update(body: "check out ##{@issue.number}") }

    @issue    = Issue.find(@issue.id)  # clear timeline cache
    timeline  = @issue.timeline_for(@owner)
    ref_items = timeline.collect { |i|  i.source if i.respond_to?(:source) }
    assert_includes ref_items, @issue2
  end

  test "issue referencing another issue on update without body change" do
    assert_equal [], @issue.timeline_for(@owner)

    perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) { @issue2.update(body: "check out ##{@issue.number}") }

    @issue.references.reload.each(&:destroy)

    perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) { @issue2.save }

    @issue    = Issue.find(@issue.id)  # clear timeline cache
    timeline  = @issue.timeline_for(@owner)
    ref_items = timeline.collect { |i|  i.source if i.respond_to?(:source) }
    assert_includes ref_items, @issue2
  end

  test "issue self-reference is ignored" do
    perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) { @issue.update(body: "check out ##{@issue.number}") }

    timeline  = @issue.timeline_for(@owner)
    ref_items = timeline.collect { |i|  i.source if i.respond_to?(:source) }
    refute_includes ref_items, @issue
  end

  test "issue comment referencing another issue" do
    perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) { create(:issue_comment, issue: @issue2, body: "check out ##{@issue.number}") }

    timeline  = @issue.timeline_for(@owner)
    ref_items = timeline.collect { |i|  i.source if i.respond_to?(:source) }
    assert_includes ref_items, @issue2
  end

  test "issue comment referencing another issue on update" do
    comment = create(:issue_comment, issue: @issue2, body: "some cool stuff")

    assert_equal [], @issue.timeline_for(@owner)

    perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) do
      comment.update(body: "check out ##{@issue.number}")
    end

    @issue    = Issue.find(@issue.id)  # clear timeline cache
    timeline  = @issue.timeline_for(@owner)
    ref_items = timeline.collect { |i|  i.source if i.respond_to?(:source) }
    assert_includes ref_items, @issue2
  end

  test "issue comment self-reference is ignored" do
    create(:issue_comment, issue: @issue, body: "check out ##{@issue.number}")

    timeline  = @issue.timeline_for(@owner)
    ref_items = timeline.collect { |i|  i.source if i.respond_to?(:source) }
    refute_includes ref_items, @issue
  end

  test "timeline does not also include IssueEvent references" do
    ref_text = "check out ##{@issue.number}"
    create(:issue, repository: @repo, body: ref_text, create_references: true)
    @issue2.update(body: ref_text)
    issue = create(:issue, repository: @repo, create_references: true)
    create(:issue_comment, issue: issue, body: ref_text)

    timeline   = @issue.timeline_for(@owner)
    ref_events = timeline.select { |i|  i.is_a?(IssueEvent) && i.reference? }
    assert_equal [], ref_events
  end

  test "timeline includes comments and visible events" do
    comment = create :issue_comment, issue: @issue, body: "hello!"
    @issue.close(@owner)
    event = @issue.events.last

    assert_equal [comment, event], @issue.timeline_for(@owner)
  end

  test "issue comment after lock isn't in timeline" do
    Timecop.freeze 3.days.ago do
      @issue.lock(@owner)
    end

    create(:issue_comment, issue: @issue2, body: "check out ##{@issue.number}")

    timeline  = @issue.timeline_for(@owner)
    ref_items = timeline.collect { |i|  i.source if i.respond_to?(:source) }
    refute_includes ref_items, @issue2
  end

  test "timeline_for only returns items newer than the specified time" do
    Timecop.freeze do
      create(:issue_comment, issue: @issue, body: "comment 1", created_at: 10.days.ago)
      create(:issue_comment, issue: @issue, body: "comment 2", created_at: 9.days.ago)
      last_comment = create(:issue_comment, issue: @issue, body: "comment 3", created_at: 27.hours.ago)

      timeline = @issue.timeline_for(@owner, since: 2.days.ago)
      assert_equal [last_comment], timeline
    end
  end

  context "commit mentions" do
    test "from private repo to issue for someone who can't see private repo" do
      owner = create :user, plan: "small"
      private_repo = create :private_repository, owner: owner, from_example: :commit_mentions

      assert commit = private_repo.commit_for_ref("master")
      assert event = @issue.reference_from_commit(private_repo.user, commit.oid, private_repo)
      # cross repository commit mention
      assert @issue.events.include?(event), "commit reference event should be recorded"

      refute event.repository_for_commit.pullable_by?(@owner), "private repo should not be pullable by owner of other repo"
      refute @issue.timeline_for(@owner).include?(event), "timeline should not include event"
    end

    test "excluded from nonexistent repositories" do
      ephemeral_repo = create :repository, owner: @owner

      assert event = @issue.reference_from_commit(@owner, GitHub::NULL_OID, ephemeral_repo)
      ephemeral_repo.remove(@owner)

      refute @issue.timeline_for(@owner).include?(event), "timeline should exclude orphaned commit ref"
    end

    test "excluded from disabled repositories" do
      repo = create :repository, from_example: :commit_mentions
      staff_user = create(:staff_admin_user)

      repo.access.disable("size", staff_user)

      assert commit = repo.commit_for_ref("master")
      assert event = @issue.reference_from_commit(create(:user), commit.oid, repo)
      refute @issue.timeline_for(@owner).include?(event), "timeline should exclude commit references from disabled repo"
    end

    test "exclude blocked user's commit mentions" do
      repo = create :repository, owner: @owner, from_example: :commit_mentions
      blocked_user = create(:user)

      @owner.block(blocked_user)

      assert commit = repo.commit_for_ref("master")
      assert event = @issue.reference_from_commit(blocked_user, commit.oid, repo)
      refute @issue.timeline_for(@owner).include?(event), "timeline should exclude mention from blocked user"
    end

    test "excludes mentions from spammy repos" do
      skip unless GitHub.spamminess_check_enabled?
      spammy_org = create(:organization, spammy: true)
      repo = create :repository, owner: spammy_org, from_example: :commit_mentions

      assert commit = repo.commit_for_ref("master")
      assert event = @issue.reference_from_commit(create(:user), commit.oid, repo)
      refute @issue.timeline_for(@owner).include?(event), "timeline should exclude commit references from spammy repo"
    end

    test "excludes references from spammy actors" do
      skip unless GitHub.spamminess_check_enabled?
      repo = create(:repository, from_example: :commit_mentions)

      spammy_user = create(:user, spammy: true)
      repo.add_member(spammy_user)

      assert commit = repo.commit_for_ref("master")
      assert event = @issue.reference_from_commit(spammy_user, commit.oid, repo)
      refute @issue.timeline_for(@owner).include?(event), "timeline should exclude commit references from spammy actors"
    end
  end

  test "PR review comments are ordered in general timeline" do
    repo = create(:repository, owner: preview_user, from_example: :simple)
    issue = create(:issue, repository: repo, create_references: true)

    base_ref = repo.heads.find("master")
    head_ref = repo.heads.create("topic", base_ref.target_oid, repo.owner)

    metadata = { message: "blah", committer: repo.owner }

    @commit = head_ref.append_commit(metadata, repo.owner) do |files|
      files.add("blah.txt", "blahblahblah")
    end

    @pull = PullRequest.create_for(repo,
      user: repo.owner,
      base: "#{repo.owner}:master",
      head: "#{repo.owner}:topic",
      title: "blah",
      body: "blah",
      issue: issue,
    )

    Timecop.freeze(T.must(@pull.created_at) + 2.hours) do
    end

    Timecop.freeze(T.must(@pull.created_at) + 4.hours) do
      @review_comment = create(:pull_request_review_comment,
        pull_request: @pull,
        user: create(:user),
        body: ":+1: totally rad!",
        commit_id: @pull.head_sha,
        path: "blah.txt",
        original_position: 1,
      ).submit!
    end

    timeline  = @pull.timeline_for(@owner)

    assert_equal @review_comment, timeline.last.comments.first
  end

  test "timeline includes events in the same order they were performed" do
    events = T.let([], T::Array[T.untyped])

    # ensure multiple events have the same time, so the same "timeline sort by"
    # and that their storage order doesn't quite match the performance order
    now = Time.now

    Timecop.freeze(now + 2.minutes) do
      @issue.close(@owner)
      events.push @issue.events.last
      @issue.open(@owner)
      events.push @issue.events.last
    end

    Timecop.freeze(now) do
      earlier_events = []

      @issue.close(@owner)
      earlier_events.push @issue.events.last
      @issue.open(@owner)
      earlier_events.push @issue.events.last
      @issue.close(@owner)
      earlier_events.push @issue.events.last

      events = earlier_events + events
    end

    assert_equal events, @issue.timeline_for(@owner)
  end

  context "project timeline events" do
    test "include project events" do
      IssueEvent.create!(issue_id: @issue.id, event: "added_to_project_v2", actor_id: @issue.owner.id, project_id: @memex_project.id, created_at: Time.now)

      timeline = @issue.timeline_model_for(@owner, filter_options)
      timeline_events = timeline.async_filtered_placeholders.sync

      assert_equal 1, timeline_events.size
    end

    test "include project events when the feature flag is enabled for the viewer of the issue" do
      viewer = create(:user)
      @repo.add_member(viewer)
      @memex_project.grant_role(viewer, :reader)

      IssueEvent.create!(issue_id: @issue.id, event: "added_to_project_v2", actor_id: @issue.owner.id, project_id: @memex_project.id, created_at: Time.now)

      timeline = @issue.timeline_model_for(viewer, filter_options)
      timeline_events = timeline.async_filtered_placeholders.sync

      assert_equal 1, timeline_events.size
    end

    test "doesn't include project events when the viewer doesn't have access to the project" do
      viewer = create(:user)
      @repo.add_member(viewer)

      IssueEvent.create!(issue_id: @issue.id, event: "added_to_project_v2", actor_id: @issue.owner.id, project_id: @memex_project.id, created_at: Time.now)

      timeline = @issue.timeline_model_for(viewer, filter_options)
      timeline_events = timeline.async_filtered_placeholders.sync

      assert_equal 0, timeline_events.size
    end

    test "returns early if has_timeline_items? is false" do
      Timeline::IssueTimeline.any_instance.expects(:async_issue_comment_placeholders).never

      timeline = @issue.timeline_model_for(@owner, filter_options)
      timeline_events = timeline.async_values.sync

      assert_equal 0, timeline_events.size
    end

    test "does not return early if has_timeline_items? is true" do
      @issue.close(@owner)
      event = @issue.events.last

      timeline = @issue.timeline_model_for(@owner, filter_options)
      timeline_events = timeline.async_values.sync

      assert_equal [event], timeline_events
    end

    test "returns project events from MySQL" do
      added_event = IssueEvent.create!(issue_id: @issue.id, event: "added_to_project_v2", actor_id: @owner.id, source_id: "a", project_id: @memex_project.id)
      converted_event = IssueEvent.create!(issue_id: @issue.id, event: "converted_from_draft", actor_id: @owner.id, source_id: "b", project_id: @memex_project.id)
      removed_event = IssueEvent.create!(issue_id: @issue.id, event: "removed_from_project_v2", actor_id: @owner.id, source_id: "c", project_id: @memex_project.id)
      status_changed_event = IssueEvent.create!(
        issue_id: @issue.id,
        event: "project_v2_item_status_changed",
        actor_id: @owner.id,
        source_id: "d",
        project_id: @memex_project.id,
        project_status: "status",
        project_previous_status: "previous_status",
      )

      timeline = @issue.timeline_model_for(@owner, filter_options)
      timeline_events = timeline.async_filtered_placeholders.sync

      assert_equal 4, timeline_events.size

      assert_equal "added_to_project_v2", timeline_events[0].event_name
      assert_equal added_event.id, timeline_events[0].id

      assert_equal "converted_from_draft", timeline_events[1].event_name
      assert_equal converted_event.id, timeline_events[1].id

      assert_equal "removed_from_project_v2", timeline_events[2].event_name
      assert_equal removed_event.id, timeline_events[2].id

      assert_equal "project_v2_item_status_changed", timeline_events[3].event_name
      assert_equal status_changed_event.id, timeline_events[3].id
    end

    test "doesn't return project events unless the show_project_events filter option is passed" do
      added_event = IssueEvent.create!(issue_id: @issue.id, event: "added_to_project_v2", actor_id: @owner.id, source_id: "a", project_id: @memex_project.id)

      timeline = @issue.timeline_model_for(@owner, filter_options.except(:show_project_events))
      timeline_events = timeline.async_filtered_placeholders.sync

      assert_empty timeline_events
    end
  end

  def filter_options
    {
      item_types: Platform::Unions::IssueTimelineItems.possible_types,
      show_project_events: true,
    }
  end

  context "#visible_events" do
    test "includes marked_as_duplicate events referred from issues in public repositories" do
      public_repo = create(:repository, owner: @owner)
      public_issue = create(:issue, repository: public_repo, create_references: true)
      event = create(:issue_event,
        event: "marked_as_duplicate",
        issue: @issue,
        subject: public_issue,
      )
      rando = create(:user)

      events = @issue.timeline_for(rando)

      assert_includes events, event
    end

    test "excludes marked_as_duplicate events referred from issues in private unreadable repositories" do
      private_repo = create(:private_repository, owner: @owner)
      private_issue = create(:issue, repository: private_repo, create_references: true)
      event = create(:issue_event,
        event: "marked_as_duplicate",
        issue: @issue,
        subject: private_issue,
      )
      rando = create(:user)

      events = @issue.timeline_for(rando)

      refute_includes events, event
    end

    test "includes marked_as_duplicate events referred from issues in private readable repositories" do
      private_repo = create(:private_repository, owner: @owner)
      private_issue = create(:issue, repository: private_repo, create_references: true)
      event = create(:issue_event,
        event: "marked_as_duplicate",
        issue: @issue,
        subject: private_issue,
      )

      events = @issue.timeline_for(@owner)

      assert_includes events, event
    end

    test "excludes marked_as_duplicate events with invalid canonical issues" do
      ephemeral_issue1 = create(:issue, repository: @repo, create_references: true)
      ephemeral_issue2 = create(:issue, repository: @repo, create_references: true)
      event = create(:issue_event,
        event: "marked_as_duplicate",
        issue: @issue,
        subject: ephemeral_issue2,
      )
      ephemeral_issue1.destroy
      ephemeral_issue2.destroy

      events = @issue.timeline_for(@owner)

      refute_includes events, event
    end

    test "excludes org project events that aren't visible to the user" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      issue = create(:issue, repository: repo, create_references: true)

      hidden_project = create(:project, owner: org)
      hidden_project_event = create(:issue_event, event: "added_to_project", issue: issue, subject: hidden_project)
      hidden_project.update_org_permission(nil)

      visible_project = create(:project, owner: org)
      visible_project_event = create(:issue_event, event: "added_to_project", issue: issue, subject: visible_project)
      visible_project.update_org_permission(:read)

      org_member = create(:user, login: "org-member")
      org.add_member(org_member)
      repo.add_member(org_member, action: :read)

      events = issue.timeline_for(org_member)

      assert_includes events, visible_project_event
      refute_includes events, hidden_project_event
    end

    test "includes connected events that are visible to the user" do
      user = create(:user)
      user_repo = create(:repository, owner: user)
      issue = create(:issue, repository: user_repo, create_references: true)

      rando = create(:user)
      private_repo = create(:private_repository, owner: rando)

      accessible_pr = create(:pull_request, :disable_disk_access, user: user, repository: user_repo)
      inaccessible_pr = create(:pull_request, :disable_disk_access, user: rando, repository: private_repo)

      ref1 = create(:manual_close_issue_reference, pull_request: accessible_pr, issue: issue, actor_id: user.id)
      visible_connected_event = issue.events.connects.detect { |e| e.subject == accessible_pr.issue }

      ref2 = create(:manual_close_issue_reference, pull_request: inaccessible_pr, issue: issue, actor_id: rando.id)
      hidden_connected_event = issue.events.connects.detect { |e| e.subject == inaccessible_pr.issue }

      events = issue.timeline_for(user)

      assert_includes events, visible_connected_event
      refute_includes events, hidden_connected_event
    end

    if GitHub.spamminess_check_enabled?
      test "excludes user_blocked events where subject is spammy" do
        spammy = create(:spammy_user)
        repo = create(:org_owned_repository)
        owner = repo.organization.admin
        issue = create(:issue, repository: repo, create_references: true)
        # we have to explictly set `created_at` to prevent these events from being
        # filtered out, see https://github.com/github/github/issues/115991#issuecomment-501523067
        visible_block_event = create(:issue_event, event: "user_blocked", issue: issue, actor: owner, subject: create(:user), created_at: 20.minutes.ago)
        spammy_block_event = create(:issue_event, event: "user_blocked", issue: issue, actor: owner, subject: spammy, created_at: 10.minutes.ago)

        events = issue.timeline_for(owner)
        assert_includes events, visible_block_event
        refute_includes events, spammy_block_event
      end

      test "includes user_blocked events where spammy subject is viewer" do
        spammy = create(:spammy_user)
        repo = create(:org_owned_repository)
        owner = repo.organization.admin
        issue = create(:issue, repository: repo, create_references: true)
        visible_block_event = create(:issue_event, event: "user_blocked", issue: issue, actor: owner, subject: create(:user), created_at: 20.minutes.ago)
        spammy_block_event = create(:issue_event, event: "user_blocked", issue: issue, actor: owner, subject: spammy, created_at: 10.minutes.ago)

        events = issue.timeline_for(spammy)
        assert_includes events, visible_block_event
        assert_includes events, spammy_block_event
      end

      test "includes user_blocked events where subject is spammy if viewer is site admin" do
        staffer = create(:staff_admin_user)
        spammy = create(:user, spammy: true)
        repo = create(:org_owned_repository)
        owner = repo.organization.admin
        issue = create(:issue, repository: repo, create_references: true)
        visible_block_event = create(:issue_event, event: "user_blocked", issue: issue, actor: owner, subject: create(:user), created_at: 20.minutes.ago)
        spammy_block_event = create(:issue_event, event: "user_blocked", issue: issue, actor: owner, subject: spammy, created_at: 10.minutes.ago)

        events = issue.timeline_for(staffer)
        assert_includes events, visible_block_event
        assert_includes events, spammy_block_event
      end
    end
  end
end
