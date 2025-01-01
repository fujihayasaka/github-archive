# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectCardTest < GitHub::TestCase
  include HydroTestHelpers
  include PrioritizationHelpers
  include GitHub::PullRequestTestHelpers
  include StringFromBinaryTestHelper

  fixtures do
    @owner = create(:user)
    @repo = create(:repository, owner: @owner)
    @project = create(:project, owner: @repo)
    @column = create(:project_column, project: @project)
    @triaged_card = create(:note_project_card, column: @column, creator: @owner)
    @pending_card = create(:pending_project_card, project: @project, content: create(:issue, repository: @repo), creator: @owner)
  end

  setup do
    GitHub.context.push(actor_id: @owner.id)
  end

  test "has content" do
    issue = create(:issue, repository: @repo)
    card = create(:project_card, column: @column, content: issue)
    assert_equal issue, card.content
  end

  test "has project set from column" do
    card = create(:project_card, column: @column)
    assert_equal @project, card.project
  end

  test "removes self from column on destroy" do
    column_2 = create(:project_column, project: @project)
    card = create(:project_card, column: column_2)
    column_2.prioritize_card!(card)
    card.destroy
    column_2.reload
    assert_predicate column_2.cards, :none?
  end

  test "is invalid if a card already exists for the same project and content" do
    issue = create(:issue, repository: @repo)
    card1 = build(:project_card, column: @column)
    card1.content = issue
    card1.save!
    card2 = build(:project_card, column: @column)
    card2.content = issue
    refute card2.valid?
    assert_equal ["already has the associated issue"], card2.errors[:project_id]
  end

  context "max_cards_per_column" do
    test "is validated on create" do
      create(:project_card, column: @column, note: "Yup")
      ProjectColumn.stub_const(:MAX_CARDS, 1) do
        card = build(:project_card, column: @column, note: "Nope")
        refute card.save
        assert_predicate card.errors[:max_cards], :present?
      end
    end

    test "is validated on column move" do
      project = create(:project)
      column = create(:project_column, project: project)
      move_to_column = create(:project_column, project: project)
      move_card = create(:project_card, column: column, note: "YUP")
      create(:project_card, column: move_to_column, note: "staying put")

      ProjectColumn.stub_const(:MAX_CARDS, 1) do
        old_priority = move_card.priority
        old_column = move_card.column
        card_after_move = move_to_column.prioritize_card!(move_card)

        assert_equal old_priority, card_after_move.priority
        assert_equal old_column, card_after_move.column
      end
    end

    test "is validated on unarchive" do
      project = create(:project)
      column = create(:project_column, project: project)
      archived = create(:project_card, column: column, note: "archived hollaaaa!")
      archived.archive
      create(:project_card, column: column, note: "staying put")

      ProjectColumn.stub_const(:MAX_CARDS, 1) do
        refute archived.unarchive
        assert_predicate archived.errors[:max_cards], :present?
      end
    end

    test "does not validate on content update" do
      project = create(:project)
      column = create(:project_column, project: project)
      card = create(:project_card, column: column, note: "sloths enjoy tea")
      card2 = create(:project_card, column: column, note: "sloths enjoy cookies")

      ProjectColumn.stub_const(:MAX_CARDS, 1) do
        card2.note = "sloths enjoy cookies and tea"
        assert card2.valid?
      end
    end

    test "does not validate on archive" do
      project = create(:project)
      column = create(:project_column, project: project)
      card = create(:project_card, column: column, note: "sloths enjoy tea")
      card2 = create(:project_card, column: column, note: "sloths enjoy cookies")

      ProjectColumn.stub_const(:MAX_CARDS, 1) do
        assert card2.archive
      end
    end

    test "does not include archived cards" do
      project = create(:project)
      column = create(:project_column, project: project)
      archived = create(:project_card, column: column, note: "archived hollaaaa!")
      archived.archive

      ProjectColumn.stub_const(:MAX_CARDS, 1) do
        card = build(:project_card, column: column, note: "YUP")
        assert card.save

        another_card = build(:project_card, column: column, note: "Nope")
        refute another_card.save
        assert_predicate another_card.errors[:max_cards], :present?
      end
    end
  end

  context "create_in_column" do
    test "can give the card the top priority" do
      bottom_card = create(:project_card, column: @column, note: "Bottom")
      @column.prioritize_card!(bottom_card)

      top_card = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "irrelevant" })

      assert_predicate top_card, :persisted?
      assert_operator top_card.priority, :>, bottom_card.priority
    end

    test "can give the card the bottom priority if specified" do
      top_card = create(:project_card, column: @column, note: "Top")
      @column.prioritize_card!(top_card)

      bottom_card = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "irrelevant" }, position: :bottom)

      assert_predicate bottom_card, :persisted?
      assert_operator top_card.priority, :>, bottom_card.priority
    end

    test "gives the card a priority in an unprioritized column" do
      existing_card = create(:project_card, column: @column, note: "irrelevant")
      @column.prioritize_card!(existing_card)
      existing_card.update_column(:priority, nil)
      @column.reload

      card = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "also irrelevant" })

      assert_predicate card, :persisted?
      refute_nil card.priority
    end

    test "saves notes with leading colons in text" do
      card = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: ":octocat: :party:" })
      assert_predicate card, :persisted?
      assert_equal ":octocat: :party:", card.note
    end

    test "saves note with emojis in text" do
      encoded_value = "👻 in the graveyard 1️⃣✌3️⃣"
      encoded_value2 = "\xF0\x9F\x91\xBB in the graveyard 1\xEF\xB8\x8F\xE2\x83\xA3\xE2\x9C\x8C3\xEF\xB8\x8F\xE2\x83\xA3"

      card = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: encoded_value })

      assert_predicate card, :persisted?
      assert_equal encoded_value, card.note
      assert_multibyte_tracked_changes(card, :note, encoded_value, encoded_value2)
    end

    test "can give the card the bottom priority if moved via automation" do
      reopened_column = create(:project_column, project: @project, name: "reopened")
      workflow = create(:project_workflow, trigger_type: ProjectWorkflow::ISSUE_REOPENED_TRIGGER, project: @project)
      workflow.set_transition_action(column: reopened_column, creator: @owner)

      top_card = create(:project_card, column: reopened_column, note: "Top")
      reopened_column.prioritize_card!(top_card)

      issue = create(:issue, repository: @repo)
      issue_card = create(:project_card, column: @column, content: issue)
      issue.close

      assert_equal @column.id, issue_card.column_id
      perform_enqueued_jobs(only: [ProcessProjectWorkflowsJob]) do
        issue.open
      end
      issue_card.reload

      assert_equal reopened_column.id, issue_card.column_id
      assert_equal 2, reopened_column.cards.count
      assert_predicate issue_card, :persisted?
      assert_operator issue_card.priority, :<, top_card.priority
    end

    test "can give the card the top priority if moved via automation to a done column" do
      done_column = create(:project_column, project: @project, name: "done")
      workflow = create(:project_workflow, trigger_type: ProjectWorkflow::ISSUE_CLOSED_TRIGGER, project: @project)
      workflow.set_transition_action(column: done_column, creator: @owner)

      bottom_card = create(:project_card, column: done_column, note: "Bottom")
      done_column.prioritize_card!(bottom_card)

      issue = create(:issue, repository: @repo)
      issue_card = create(:project_card, column: @column, content: issue)

      assert_equal @column.id, issue_card.column_id
      perform_enqueued_jobs(only: [ProcessProjectWorkflowsJob]) do
        issue.close
      end
      issue_card.reload

      assert_equal done_column.id, issue_card.column_id
      assert_equal 2, done_column.cards.count
      assert_predicate issue_card, :persisted?
      assert_operator issue_card.priority, :>, bottom_card.priority
    end

    test "can give the card the top priority if moved manually" do
      bottom_card = create(:project_card, column: @column, note: "Bottom")
      @column.prioritize_card!(bottom_card)

      top_card = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "irrelevant" })

      assert_predicate top_card, :persisted?
      assert_operator top_card.priority, :>, bottom_card.priority
    end

    test "can give the card a middle priority" do
      top_card = create(:project_card, column: @column, note: "Top")
      @column.prioritize_card!(top_card)

      bottom_card = create(:project_card, column: @column, note: "Bottom")
      @column.prioritize_card!(bottom_card, position: :bottom)

      middle_card = ProjectCard.create_in_column(@column,
        creator: @owner,
        content_params: { content_type: "Note", note: "Middle" },
        after: top_card,
      )

      assert_predicate middle_card, :persisted?
      assert_operator top_card.priority, :>, middle_card.priority
      assert_operator middle_card.priority, :>, bottom_card.priority
    end

  end

  context "live updates for issues" do
    test "should be triggered on create" do
      Timecop.freeze do
        issue = create(:issue, repository: @repo)
        issue.reload
        data = {
          timestamp: Time.now.to_i,
          reason:    "issue ##{issue.id} updated",
          wait:      issue.default_live_updates_wait,
          gid:       issue.global_relay_id,
        }

        channel = GitHub::WebSocket::Channels.issue(issue)

        GitHub::WebSocket.stubs(:notify_issue_channel)
        GitHub::WebSocket.expects(:notify_issue_channel).with(issue, channel, data).returns([]).once
        create(:project_card, column: @column, content: issue)
      end
    end

    test "should be triggered on destroy" do
      issue = create(:issue, repository: @repo)
      issue.reload
      card = create(:project_card, column: @column, content: issue)

      Timecop.freeze do
        data = {
          timestamp: Time.now.to_i,
          reason:    "issue ##{issue.id} updated",
          wait:      issue.default_live_updates_wait,
          gid:       issue.global_relay_id,
        }

        channel = GitHub::WebSocket::Channels.issue(issue)

        GitHub::WebSocket.stubs(:notify_issue_channel)
        GitHub::WebSocket.expects(:notify_issue_channel).with(issue, channel, data).returns([]).once

        card.destroy
      end
    end

    test "should log time in triage when added to column" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      card = create(:pending_project_card)

      Timecop.freeze(2.days.from_now) do
        @column.prioritize_card!(card)
      end

      assert GitHub.dogstats.distributions("project_card.dist.triage_time").length == 1
    end

    test "should be triggered on column move" do
      issue = create(:issue, repository: @repo)
      issue.reload
      card = create(:project_card, column: @column, content: issue)
      other_column = create(:project_column, project: card.project)

      Timecop.freeze do
        data = {
          timestamp: Time.now.to_i,
          reason:    "issue ##{issue.id} updated",
          wait:      issue.default_live_updates_wait,
          gid:       issue.global_relay_id,
        }

        channel = GitHub::WebSocket::Channels.issue(issue)

        GitHub::WebSocket.stubs(:notify_issue_channel)
        GitHub::WebSocket.expects(:notify_issue_channel).with(issue, channel, data).returns([]).once

        other_column.prioritize_card!(card)
      end
    end

    test "should not be triggered on move within the same column" do
      issue = create(:issue, repository: @repo)
      card = create(:project_card, column: @column, content: issue)
      other_card = create(:project_card, column: @column, note: "Hello")

      allow_transaction_nesting do
        @column.prioritize_card!(other_card)
        @column.prioritize_card!(card)

        Timecop.freeze do
          data = { timestamp: Time.now.to_i, reason: "issue ##{issue.id} updated" }
          channel = GitHub::WebSocket::Channels.issue(issue)

          GitHub::WebSocket.stubs(:notify_issue_channel).returns([])
          GitHub::WebSocket.expects(:notify_issue_channel).with(issue, channel, data).returns([]).never

          @column.prioritize_card!(card, after: other_card)
        end
      end
    end
  end

  context "#channel" do
    test "includes channels for any cross references in the note text" do
      other_repo = create(:repository, owner: @owner)
      issue1 = create(:issue, repository: other_repo)
      issue2 = create(:issue, repository: other_repo)
      card = create(:project_card, note: "Read #{issue1.url} and #{issue2.url}", project: @project)
      channels = card.channel(viewer: @owner)
      assert_includes channels, GitHub::WebSocket::Channels.issue(issue1)
      assert_includes channels, GitHub::WebSocket::Channels.issue(issue2)
      assert_includes channels, GitHub::WebSocket::Channels.project_card(card)
    end

    test "includes channels for close_issue_references for an issue card" do
      issue = create(:issue, repository: @repo)
      card = create(:project_card, content: issue)
      channels = card.channel(viewer: @owner)
      assert_includes channels, GitHub::WebSocket::Channels.close_issue_references(issue)
    end

    test "does not include channels for close_issue_references for a pr card" do
      pull = make_pr_and_repos
      card = create(:project_card, content: pull.issue)
      channels = card.channel(viewer: @owner)
      refute_includes channels, GitHub::WebSocket::Channels.close_issue_references(pull)
    end
  end

  context ".filtered scope" do
    test "defaults return all cards" do
      cards = @project.cards.filtered
      assert_same_elements cards.pluck(:id), [@pending_card.id, @triaged_card.id]
    end

    test "include_triaged false returns pending" do
      cards = @project.cards.filtered(include_triaged: false)
      assert_same_elements cards.pluck(:id), [@pending_card.id]
    end

    test "include_pending false returns triaged" do
      cards = @project.cards.filtered(include_pending: false)
      assert_same_elements cards.pluck(:id), [@triaged_card.id]
    end

    test "include_pending false, include_triaged false returns nothing" do
      cards = @project.cards.filtered(include_pending: false, include_triaged: false)
      assert_empty cards
    end
  end

  context "safe_creator" do
    test "returns the creator when there is one" do
      card = create(:note_project_card, column: @column, creator: @owner)

      assert_equal @owner, card.safe_creator
    end

    test "returns the ghost user when there's no creator" do
      card = create(:note_project_card, column: @column, creator: @owner)
      card.update_column(:creator_id, nil)
      card.reload

      assert_equal User.ghost, card.safe_creator
    end
  end

  context "#can_convert_to_issue?" do
    test "is true for notes in repos with issues enabled" do
      card = create(:note_project_card, note: "Hello", column: @column)
      assert card.can_convert_to_issue?(converter: @owner)
    end

    test "is true for notes in user projects when the user has a repo with issues enabled" do
      user_project = create(:project, owner: @owner)
      card = create(:note_project_card, note: "Hello", project: user_project)

      assert card.can_convert_to_issue?(converter: @owner)
    end

    test "is false for non-notes" do
      card = create(:project_card, column: @column)
      refute card.can_convert_to_issue?(converter: @owner)
    end

    test "is false for notes in repos with issues disabled" do
      @repo.has_issues = false
      @repo.save!

      card = create(:note_project_card, note: "Hello", column: @column)
      refute card.can_convert_to_issue?(converter: @owner)
    end

    test "false if user cannot view any repositories in the org" do
      member = create(:user)
      org = create(:organization)
      org.add_member(member, action: :read)
      org.update_default_repository_permission(:none, actor: org.admins.first)
      not_visible_repo = create(:private_repository, owner: org)
      project = create(:project, owner: org)
      column = create(:project_column, project: project)
      card = create(:project_card, column: column, note: "hello")
      refute card.can_convert_to_issue?(converter: member)
    end

    if GitHub.email_verification_enabled?
      test "false if user must verify email" do
        GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
        unverified_user = create(:user)
        card = create(:note_project_card)
        repo = card.project.owner
        repo.add_member(unverified_user)

        assert_predicate unverified_user, :must_verify_email?
        refute card.can_convert_to_issue?(converter: unverified_user)
      end
    end
  end

  context "convert_to_note_reference!" do
    test "sets the note to be URL of the issue and clears the content on public repos" do
      issue = create(:issue, repository: @repo)
      card = create(:project_card, column: @column, content: issue)
      card.convert_to_note_reference!

      assert_nil card.content
      assert_equal issue.url, card.note
    end

    test "does nothing when called on a private repo issue card" do
      org = create(:organization, plan: "silver", admin: @owner)
      repo = create(:private_repository, owner: org)
      project = create(:project, owner: org)
      column = create(:project_column, project: project)
      issue = create(:issue, repository: repo)
      card = create(:project_card, column: column, content: issue)
      card.convert_to_note_reference!
      card.reload
      assert_equal issue, card.content
      assert_nil card.note
    end

    test "trigger_issue_removed_from_project_event" do
      issue = create(:issue, repository: @repo)
      card = create(:project_card, column: @column, content: issue)
      card.convert_to_note_reference!

      event = issue.events.last
      assert_equal "removed_from_project", event.event
      assert_equal card.project, event.subject
      assert_equal @column.name, event.column_name
      assert_equal card.id, event.card_id
      assert_equal @owner, event.actor
    end

    test "does nothing if card is already a note" do
      card = create(:note_project_card, note: "Hello", column: @column)
      card.convert_to_note_reference!

      assert_nil card.content
      assert_equal "Hello", card.note
    end
  end

  context "content validation" do
    test "requires content when no note" do
      card = build(:project_card, column: @column, content: nil, note: "")
      refute_predicate card, :valid?
      refute_empty card.errors[:note]

      card.note = "Hello!"
      assert_predicate card, :valid?
    end

    test "validates note when content blank" do
      card = build(:project_card, column: @column, content: nil, note: " ")
      refute_predicate card, :valid?
      refute_empty card.errors[:note]
      assert_empty card.errors[:project_id]
    end

    test "validates project_id when content is not blank" do
      issue = create(:issue, repository: @repo)
      create(:project_card, column: @column, content: issue, note: nil)
      card = build(:project_card, column: @column, content: issue, note: nil)
      refute_predicate card, :valid?
      assert_empty card.errors[:note]
      refute_empty card.errors[:project_id]
    end
  end

  context "set_content_from" do
    test "can set an issue as content" do
      issue = create(:issue, repository: @repo)
      card = build(:project_card, column: @column, project: @project)
      card.set_content_from(actor: @owner, params: { content_type: "Issue", content_id: issue.id })
      assert_equal issue, card.content
    end
  end

  context "archived scope" do
    test "only shows archived cards" do
      unarchived_card = create(:project_card, project: @project, column: @column, content: nil, note: "unarchived")
      archived_card = create(:project_card, project: @project, column: @column, content: nil, note: "archived")
      archived_card.archive

      assert_includes @column.cards.archived, archived_card
      refute_includes @column.cards.archived, unarchived_card
    end
  end

  context "not_archived scope" do
    test "only shows unarchived cards" do
      unarchived_card = create(:project_card, project: @project, column: @column, content: nil, note: "unarchived")
      archived_card = create(:project_card, project: @project, column: @column, content: nil, note: "archived")
      archived_card.archive

      assert_includes @column.cards.not_archived, unarchived_card
      refute_includes @column.cards.not_archived, archived_card
    end
  end

  context "transfer_issue_card" do
    test "noop for a repo project card" do
      issue = create(:issue, repository: @repo)
      card = create(:project_card, column: @column, content: issue)
      new_issue = create(:issue, repository: @repo)

      assert_no_difference -> { @project.cards.count } do
        card.transfer_issue_card(new_issue.id)
      end
    end

    test "does not create a new card" do
      issue = create(:issue, repository: @repo)
      project = create(:project, owner: @owner)
      column = create(:project_column, project: project)
      card = create(:project_card, column: column, content: issue)
      new_issue = create(:issue, repository: @repo)

      card.transfer_issue_card(new_issue.id)
      card.reload
      new_issue.reload

      assert_same_elements [card], new_issue.cards
    end

    test "transfers a pending card successfully" do
      issue = create(:issue, repository: @repo)
      project = create(:project, owner: @owner)
      card = create(:pending_project_card, project: project, content: issue)
      new_issue = create(:issue, repository: @repo)

      card.transfer_issue_card(new_issue.id)
      card.reload

      assert card.pending?
      refute card.archived?
      assert_equal project, card.project
    end

    test "stays in the same priority position" do
      issue = create(:issue, repository: @repo)
      project = create(:project, owner: @owner)
      column = create(:project_column, project: project)
      card = create(:project_card, column: column, content: issue)
      new_issue = create(:issue, repository: @repo)

      old_priority = card.priority
      card.transfer_issue_card(new_issue.id)
      card.reload

      assert_equal old_priority, card.priority
    end

    test "transfers an archived card successfully" do
      issue = create(:issue, repository: @repo)
      project = create(:project, owner: @owner)
      column = create(:project_column, project: project)
      card = create(:project_card, column: column, content: issue)
      new_issue = create(:issue, repository: @repo)

      card.archive
      card.transfer_issue_card(new_issue.id)
      card.reload

      assert card.archived?
      assert_equal column, card.column
      assert_nil card.priority
    end
  end

  context "archived?" do
    test "returns true for an archived card" do
      card = create(:project_card, project: @project, column: @column)
      card.archive

      assert_predicate card, :archived?
    end

    test "returns false for an unarchived card" do
      card = create(:project_card, project: @project, column: @column)
      refute_predicate card, :archived?
    end
  end

  context "archive" do
    test "archives an unarchived the card" do
      card = create(:project_card, project: @project, column: @column)
      refute_predicate card, :archived?

      card.archive
      assert_predicate card, :archived?
    end

    test "clears the card's priority" do
      card = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "irrelevant" })
      card.archive
      card.reload

      assert_nil card.priority
      refute_includes @column.cards.where("priority IS NOT NULL").by_priority, card
    end

    test "no-ops on an archived card" do
      card = create(:project_card, project: @project, column: @column)
      card.archive
      assert_predicate card, :archived?

      card.archive
      assert_predicate card, :archived?
    end

    test "sends metrics to DataDog to make pretty charts" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      Timecop.freeze(5.days.ago) do
        column = create(:project_column, purpose: ProjectColumn::PURPOSES.first)
        @note = create(:project_card, note: "hooray", column: column)
        @issue = create :project_card
      end

      card_age = 2
      Timecop.freeze(@note.created_at + card_age.days) do
        @note.archive
        @issue.archive
      end

      increments = GitHub.dogstats.increments("projects.archived_card")
      note_tags = increments.first.tags.to_a
      issue_tags = increments.second.tags.to_a

      assert_equal "content_type:note", note_tags.first
      assert_equal "column_purpose:#{ProjectColumn::PURPOSES.first}", note_tags.second
      assert_equal "content_type:issue", issue_tags.first

      histograms = GitHub.dogstats.histograms("projects.archived_card_age")
      assert_equal [card_age, card_age], histograms.map(&:value)
    end
  end

  context "unarchive" do
    test "unarchives an archived card" do
      card = create(:project_card, project: @project, column: @column)
      card.archive
      assert allow_transaction_nesting { card.unarchive }
      refute_predicate card, :archived?
    end

    test "moves the unarchived card to the bottom of the column" do
      card = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "irrelevant" })

      # Make sure there's more than one card in the column so that top and
      # bottom aren't the same
      assert_operator @column.cards.size, :>, 1

      card.archive
      allow_transaction_nesting { card.unarchive }
      @column.reload

      # Gets moved to the bottom
      assert_equal card, @column.cards.by_priority.last
    end

    test "can unarchive to the middle of a different column" do
      archived_card = create(:project_card, project: @project, column: @column)
      archived_card.archive

      different_column = create(:project_column, project: @project)
      bottom_card = ProjectCard.create_in_column(different_column, creator: @owner, content_params: { content_type: "Note", note: "bottom card" })
      top_card = ProjectCard.create_in_column(different_column, creator: @owner, content_params: { content_type: "Note", note: "top card" })
      archived_card.unarchive(into_column: different_column, after: top_card)
      archived_card.reload

      assert_equal [top_card, archived_card, bottom_card], different_column.cards.by_priority
      assert_equal different_column, archived_card.column
    end

    test "no-ops on an unarchived card" do
      card = create(:project_card, project: @project, column: @column)
      assert allow_transaction_nesting { card.unarchive }
      refute_predicate card, :archived?
    end

    test "sends metrics to DataDog to make pretty charts" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      Timecop.freeze(10.days.ago) do
        column = create(:project_column, purpose: ProjectColumn::PURPOSES.first)
        @note = create(:project_card, note: "hooray", column: column)
      end

      card_age = 2
      Timecop.freeze(@note.created_at + card_age.days) { @note.archive }

      archive_age = 4
      Timecop.freeze(@note.archived_at + archive_age.days) { @note.unarchive }

      increments = GitHub.dogstats.increments("projects.unarchived_card")
      note_tags = increments.first.tags.to_a
      assert_equal "column_purpose:#{ProjectColumn::PURPOSES.first}", note_tags.first

      histograms = GitHub.dogstats.histograms("projects.unarchived_card_after")
      assert_equal [archive_age], histograms.map(&:value)
    end

    test "errors if the column has max cards" do
      project = create(:project)
      column = create(:project_column, project: project)
      archived = create(:project_card, column: column, note: "archived hollaaaa!")
      archived.archive
      create(:project_card, column: column, note: "a real card, yay")

      ProjectColumn.stub_const(:MAX_CARDS, 1) do
        refute archived.unarchive
        assert_predicate archived.errors[:max_cards], :present?
      end
    end
  end

  context "attrs_for_filter" do
    context "keys" do
      test "is empty when redaction hasn't passed" do
        card = create(:project_card, column: @column, note: "Yup")
        assert_empty card.attrs_for_filter.keys
      end

      test "contains the expected keys for a note card" do
        card = create(:project_card, column: @column, note: "Yup")
        card.passed_redaction = true

        expected_keys = %i(author is state title type)

        assert_same_elements expected_keys, card.attrs_for_filter.keys
      end

      test "contains the expected keys for an issue card" do
        issue = create(:issue, repository: @repo)
        card = create(:project_card, column: @column, content: issue)
        card.passed_redaction = true

        expected_keys = %i(assignee author is label repo state title type)

        assert_same_elements expected_keys, card.attrs_for_filter.keys
      end
    end

    context "assignee" do
      test "is nil for a note card" do
        card = create(:project_card, column: @column, note: "Yup")
        card.passed_redaction = true

        assert_nil card.attrs_for_filter[:assignee]
      end

      test "is empty for an issue card with no assignees" do
        issue = create(:issue, repository: @repo)
        card = create(:project_card, column: @column, content: issue)
        card.passed_redaction = true

        assert_empty card.attrs_for_filter[:assignee]
      end

      test "contains the logins of all the issue card's assignees" do
        issue = create(:issue, repository: @repo)
        assignees = Array.new(2) do |i|
          user = create(:user, login: "assignee-#{i}")
          @repo.add_member(user)

          user
        end
        issue.add_assignees(assignees)
        issue.reload

        card = create(:project_card, column: @column, content: issue)
        card.passed_redaction = true

        assert_same_elements assignees.map(&:login), card.attrs_for_filter[:assignee]
      end
    end

    context "author" do
      test "is the card creator for a note card" do
        creator = create(:user, login: "creator")
        @repo.add_member(creator)

        card = create(:project_card, column: @column, creator: creator, note: "Yup")
        card.passed_redaction = true

        assert_equal creator.login, card.attrs_for_filter[:author]
      end

      test "is the issue creator for an issue card" do
        card_creator = create(:user, login: "card-creator")
        @repo.add_member(card_creator)

        issue_creator = create(:user, login: "issue-creator")
        @repo.add_member(issue_creator)

        issue = create(:issue, repository: @repo, user: issue_creator)
        card = create(:project_card, column: @column, creator: card_creator, content: issue)
        card.passed_redaction = true

        assert_equal issue_creator.login, card.attrs_for_filter[:author]
      end
    end

    context "is" do
      test "is the type and state values combined" do
        card = create(:project_card, column: @column, note: "Yup")
        card.passed_redaction = true

        assert_same_elements %w(open note), card.attrs_for_filter[:is]
      end

      test "contains draft for draft pull requests" do
        pull = make_pr_and_repos
        pull.update_attribute(:draft, true)
        project = create(:project, owner: pull.repository)
        column = create(:project_column, project: project)
        card = create(:project_card, column: column, content: pull.issue)
        card.passed_redaction = true

        assert_same_elements %w(open draft pr), card.attrs_for_filter[:is]
      end
    end

    context "label" do
      test "is nil for a note card" do
        card = create(:project_card, column: @column, note: "Yup")
        card.passed_redaction = true

        assert_nil card.attrs_for_filter[:label]
      end

      test "is empty for an issue card with no labels" do
        issue = create(:issue, repository: @repo)
        card = create(:project_card, column: @column, content: issue)
        card.passed_redaction = true

        assert_empty card.attrs_for_filter[:label]
      end

      test "contains the names of all the issue card's labels" do
        label1 = create(:label, repository: @repo, name: "bug")
        label2 = create(:label, repository: @repo, name: "enhancement")
        label3 = create(:label, repository: @repo, name: "multi word label")
        issue = create(:issue, repository: @repo)
        issue.labels = [label1, label2, label3]

        card = create(:project_card, column: @column, content: issue)
        card.passed_redaction = true

        assert_same_elements ["bug", "enhancement", "multi word label"], card.attrs_for_filter[:label]
      end
    end

    context "milestone" do
      test "is nil for a note card" do
        card = create(:project_card, column: @column, note: "Yup")
        card.passed_redaction = true

        assert_nil card.attrs_for_filter[:milestone]
      end

      test "is nil for an issue card with no milestone" do
        issue = create(:issue, repository: @repo)
        card = create(:project_card, column: @column, content: issue)
        card.passed_redaction = true

        assert_nil card.attrs_for_filter[:milestone]
      end

      test "contains the name of the issue card's milestone" do
        milestone = create(:milestone, repository: @repo, title: "horcrux destruction")
        issue = create(:issue, repository: @repo)
        issue.milestone = milestone

        card = create(:project_card, column: @column, content: issue)
        card.passed_redaction = true

        assert_equal "horcrux destruction", card.attrs_for_filter[:milestone]
      end
    end

    context "repo" do
      test "is nil for a note card" do
        card = create(:project_card, column: @column, note: "Yup")
        card.passed_redaction = true

        assert_nil card.attrs_for_filter[:repo]
      end

      test "is the issue's repo's lowercased name-with-owner for an issue card" do
        issue = create(:issue, repository: @repo)
        card = create(:project_card, column: @column, content: issue)
        card.passed_redaction = true

        assert_equal @repo.name_with_owner.downcase, card.attrs_for_filter[:repo]
      end
    end

    context "review" do
      test "is nil for a note card" do
        card = create(:project_card, column: @column, note: "Yup")
        card.passed_redaction = true

        assert_nil card.attrs_for_filter[:review]
      end

      test "is nil for an issue card" do
        issue = create(:issue, repository: @repo)
        card = create(:project_card, column: @column, content: issue)
        card.passed_redaction = true

        assert_nil card.attrs_for_filter[:review]
      end

      test "is none when no reviews and reviews are not required" do
        pull = make_pr_and_repos
        repo = pull.repository
        project = create(:project, owner: repo)
        column = create(:project_column, project: project)
        card = create(:project_card, column: column, content: pull.issue)
        card.passed_redaction = true

        assert_equal ["none"], card.attrs_for_filter[:review]
      end

      test "is required when review is required" do
        pull = make_pr_and_repos
        create(:protected_branch, repository: pull.repository, name: "master", pull_request_reviews_enforcement_level: :everyone)
        project = create(:project, owner: pull.repository)
        column = create(:project_column, project: project)
        card = create(:project_card, column: column, content: pull.issue)
        card.passed_redaction = true

        assert_same_elements %w[none required], card.attrs_for_filter[:review]
      end

      test "is approved when changes have been approved" do
        pull = make_pr_and_repos
        create(:protected_branch, repository: pull.repository, name: "master", pull_request_reviews_enforcement_level: :everyone)
        reviewer = create(:user)
        pull.repository.add_member(reviewer)
        create(:pull_request_review, pull_request: pull, user: reviewer).approve!
        project = create(:project, owner: pull.repository)
        column = create(:project_column, project: project)
        card = create(:project_card, column: column, content: pull.issue)
        card.passed_redaction = true

        assert_same_elements ["approved"], card.attrs_for_filter[:review]
      end

      test "is changes_requested when changes have been requested" do
        pull = make_pr_and_repos
        create(:protected_branch, repository: pull.repository, name: "master", pull_request_reviews_enforcement_level: :everyone)
        reviewer = create(:user)
        pull.repository.add_member(reviewer)
        create(:pull_request_review, pull_request: pull, user: reviewer).request_changes!
        project = create(:project, owner: pull.repository)
        column = create(:project_column, project: project)
        card = create(:project_card, column: column, content: pull.issue)
        card.passed_redaction = true

        assert_same_elements ["changes_requested"], card.attrs_for_filter[:review]
      end
    end

    context "state" do
      test "is open for a note card" do
        card = create(:project_card, column: @column, note: "Yup")
        card.passed_redaction = true

        assert_equal "open", card.attrs_for_filter[:state]
      end

      test "is open for an open issue card" do
        issue = create(:issue, repository: @repo)
        card = create(:project_card, column: @column, content: issue)
        card.passed_redaction = true

        assert_equal "open", card.attrs_for_filter[:state]
      end

      test "is closed for a closed issue card" do
        issue = create(:issue, repository: @repo)
        issue.close
        card = create(:project_card, column: @column, content: issue)
        card.passed_redaction = true

        assert_equal "closed", card.attrs_for_filter[:state]
      end

      test "is closed for a closed-but-unmerged pull request card" do
        pull = make_pr_and_repos
        pull.close(pull.user)

        repo = pull.repository
        project = create(:project, owner: repo)
        column = create(:project_column, project: project)
        card = create(:project_card, column: column, content: pull.issue)
        card.passed_redaction = true

        assert_same_elements %w(closed), card.attrs_for_filter[:state]
      end

      test "is merged and closed for a closed-and-merged pull request card" do
        pull = make_pr_and_repos
        pull.merge

        repo = pull.repository
        project = create(:project, owner: repo)
        column = create(:project_column, project: project)
        card = create(:project_card, column: column, content: pull.issue)
        card.passed_redaction = true

        assert_same_elements %w(closed merged), card.attrs_for_filter[:state]
      end
    end

    context "status" do
      test "is nil for a note card" do
        card = create(:project_card, column: @column, note: "Yup")
        card.passed_redaction = true

        assert_nil card.attrs_for_filter[:status]
      end

      test "is nil for an issue card" do
        issue = create(:issue, repository: @repo)
        card = create(:project_card, column: @column, content: issue)
        card.passed_redaction = true

        assert_nil card.attrs_for_filter[:status]
      end

      test "is pending/sucess/failure for a pull request card based on the combined status of the head sha" do
        pull = make_pr_and_repos
        repo = pull.repository
        project = create(:project, owner: repo)
        column = create(:project_column, project: project)
        card = create(:project_card, column: column, content: pull.issue)
        card.passed_redaction = true

        create(:status, sha: pull.head_sha, state: "success", creator: @owner, repository: repo)
        assert_equal "success", card.attrs_for_filter[:status]

        create(:status, sha: pull.head_sha, state: "pending", creator: @owner, repository: repo)
        card.reload
        assert_equal "pending", card.attrs_for_filter[:status]

        create(:status, sha: pull.head_sha, state: "failure", creator: @owner, repository: repo)
        card.reload
        assert_equal "failure", card.attrs_for_filter[:status]
      end
    end

    context "title" do
      test "is whitespace-delimited lowercased markdown-stripped note for a note card" do
        card = create(:project_card, column: @column, note: "We can make **bold** text with Markdown.")
        card.passed_redaction = true

        assert_same_elements %w(we can make bold text with markdown.), card.attrs_for_filter[:title]
      end

      test "is whitespace-delimited lowercased issue title, number, and #-prefixed number for an issue card" do
        issue = create(:issue, repository: @repo, title: "Markdown is **meaningless** in Issue titles.")
        card = create(:project_card, column: @column, content: issue)
        card.passed_redaction = true

        expected_title_elements = %w(markdown is **meaningless** in issue titles.)
        expected_title_elements += [issue.number.to_s, "##{issue.number}"]

        assert_same_elements expected_title_elements, card.attrs_for_filter[:title]
      end

      test "is whitespace-delimited when a note card has extra spaces" do
        card = create(:project_card, column: @column, note: "a  card with   spaces")
        card.passed_redaction = true

        assert_same_elements %w(a card with spaces), card.attrs_for_filter[:title]
      end

      test "is whitespace-delimited when a note card has line breaks" do
        card = create(:project_card, column: @column, note: "a card with \nmany \nmany \nnew \nlines!")
        card.passed_redaction = true

        assert_same_elements %w(a card with many many new lines!), card.attrs_for_filter[:title]
      end

      test "is delimited correctly with tab characters" do
        card = create(:project_card, column: @column, note: "a card with \ta tab")
        card.passed_redaction = true

        assert_same_elements %w(a card with a tab), card.attrs_for_filter[:title]
      end

      test "is delimited correctly with tabs, spaces, and newlines combined" do
        card = create(:project_card, column: @column, note: "a card with \ta tab \nnewline and   spaces")
        card.passed_redaction = true

        assert_same_elements %w(a card with a tab newline and spaces), card.attrs_for_filter[:title]
      end
    end

    context "type" do
      test "is note for a note card" do
        card = create(:project_card, column: @column, note: "Yup")
        card.passed_redaction = true

        assert_equal "note", card.attrs_for_filter[:type]
      end

      test "is issue for an issue card" do
        issue = create(:issue, repository: @repo)
        card = create(:project_card, column: @column, content: issue)
        card.passed_redaction = true

        assert_equal "issue", card.attrs_for_filter[:type]
      end

      test "is pr for a pull request card" do
        pull = make_pr_and_repos
        repo = pull.repository
        project = create(:project, owner: repo)
        column = create(:project_column, project: project)
        card = create(:project_card, column: column, content: pull.issue)
        card.passed_redaction = true

        assert_equal "pr", card.attrs_for_filter[:type]
      end
    end

    context "linked" do
      test "linked pr for an issue card with xref" do
        pull = make_pr_and_repos
        issue = create(:issue, repository: pull.repository)
        issue.close_issue_references.create(pull_request: pull)
        card = create(:project_card, column: @column, content: issue)
        card.passed_redaction = true

        assert_equal "pr", card.attrs_for_filter[:linked]
      end

      test "no linked filter for an issue card without xref" do
        issue = create(:issue, repository: @repo)
        card = create(:project_card, column: @column, content: issue)
        card.passed_redaction = true

        refute card.attrs_for_filter[:linked]
      end

      test "no linked filter for a pr card with xref" do
        pull = make_pr_and_repos
        issue = create(:issue, repository: pull.repository)
        pull.close_issue_references.create(issue: issue)
        card = create(:project_card, column: @column, content: pull.issue)
        card.passed_redaction = true

        # We currently don't support xref data for PRs
        refute card.attrs_for_filter[:linked]
      end

      test "no linked filter for a pr card without xref" do
        pull = make_pr_and_repos
        card = create(:project_card, column: @column, content: pull.issue)
        card.passed_redaction = true

        refute card.attrs_for_filter[:linked]
      end
    end
  end

  context "instrumentation" do
    test "instruments project card creation" do
      events = subscribe "project_card.create"
      card = create(:project_card, column: @column, note: "well hello there", creator: @owner)

      expected_payload = {
        project_card_id: card.id,
        note: card.note,
        content_type: card.content_type,
        content_id: card.content_id,
        project_column: @column.name,
        project_column_id: @column.id,
        project: @project.name,
        project_id: @project.id,
        actor: @owner.login,
        actor_id: @owner.id,
        rank: 3,
      }
      assert event = events.pop, "an event was expected"
      assert_equal "project_card.create", event.name
      assert_equal expected_payload, event.payload
    end

    test "doesn't instrument creation when card is pending" do
      events = subscribe "project_card.create"
      assert_no_difference -> { events.size } do
        create(:pending_project_card)
      end
    end

    test "instruments project card update" do
      events = subscribe "project_card.update"
      card = create(:project_card, column: @column, note: "well hello there", creator: @owner)
      card.update_attribute(:note, "Are you sure this is a good idea?")

      assert event = events.pop, "an event was expected"
      assert_equal "project_card.update", event.name
      refute_nil event.payload[:changes]
      assert_nil event.payload[:content_url]
      assert_equal "Are you sure this is a good idea?", event.payload[:changes][:note]
    end

    test "instruments project card move" do
      events = subscribe "project_card.move"
      card_1 = create(:project_card, column: @column, creator: @owner)
      card_2 = create(:project_card, column: @column, creator: @owner)
      @column.prioritize_card!(card_1, after: card_2)

      assert event = events.pop, "an event was expected"
      assert_equal "project_card.move", event.name
      assert_equal card_2.id, event.payload[:after_id]
    end

    test "instruments archiving" do
      events = subscribe "project_card.archive"
      card = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "irrelevant" })
      card.archive

      assert_equal "project_card.archive", events.last.name
    end

    test "instruments unarchiving" do
      events = subscribe "project_card.restore"
      card = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "irrelevant" })
      card.archive
      card.unarchive

      assert_equal "project_card.restore", events.last.name
    end

    test "does not instrument inter-column card move when ghost user" do
      GitHub.context.reset
      events = subscribe "project_card.move"
      card_1 = create(:project_card, column: @column, creator: @owner)
      card_2 = create(:project_card, column: @column, creator: @owner)
      @column.prioritize_card!(card_1, after: card_2)

      refute event = events.pop, "an event was not expected"
    end

    test "instruments pending project card move" do
      issue = create(:issue, repository: @repo)
      card = create(:pending_project_card, project: @project, content: issue, creator: @owner)

      events = subscribe "project_card.create"
      @column.prioritize_card!(card)

      assert event = events.pop, "an event was expected"
      assert_equal "project_card.create", event.name
      assert_nil event.payload[:changes]
    end

    test "instruments pending project card created" do
      issue = create(:issue, repository: @repo)
      events = subscribe "project_card.pending_create"

      card = create(:pending_project_card, project: @project, content: issue, creator: @owner)

      assert event = events.pop, "an event was expected"
      assert_equal "project_card.pending_create", event.name
      assert_nil event.payload[:changes]
    end

    test "instruments project card destroy" do
      events = subscribe "project_card.delete"
      issue = create(:issue, repository: @repo)
      card = create(:project_card, column: @column, content: issue, creator: @owner)

      expected_payload = {
        project_card_id: card.id,
        note: card.note,
        content_type: card.content_type,
        content_id: card.content_id,
        content_url: card.content.url,
        project_column: @column.name,
        project_column_id: @column.id,
        project: @project.name,
        project_id: @project.id,
        rank: 3,
      }
      card.destroy

      assert event = events.pop, "an event was expected"
      assert_equal "project_card.delete", event.name
      assert_equal expected_payload, event.payload
    end

    test "doesn't instrument deletion when card is pending" do
      card = create(:pending_project_card)
      events = subscribe "project_card.delete"
      assert_no_difference -> { events.size } do
        card.destroy
      end
    end
  end

  context "trigger_moved_event" do
    test "publishes to hydro on non automated project card move", skip_enterprise: true do
      done_column = create(:project_column, project: @project)
      card = create(:project_card, column: done_column, creator: @owner)
      card.trigger_moved_event(after_card: nil, previous_column: @column, automated: false)

      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(@owner),
        automated: false,
        card: Hydro::EntitySerializer.project_card(card),
        project: Hydro::EntitySerializer.project(@project),
        source_column: Hydro::EntitySerializer.project_column(@column),
        target_column: Hydro::EntitySerializer.project_column(done_column),
      }, schema: "github.projects.v0.ProjectCardMove")
    end

    test "publishes to hydro on automated project card move", skip_enterprise: true do
      done_column = create(:project_column, project: @project)
      card = create(:project_card, column: done_column, creator: @owner)
      card.trigger_moved_event(after_card: nil, previous_column: @column, automated: true)

      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(@owner),
        automated: true,
        card: Hydro::EntitySerializer.project_card(card),
        project: Hydro::EntitySerializer.project(@project),
        source_column: Hydro::EntitySerializer.project_column(@column),
        target_column: Hydro::EntitySerializer.project_column(done_column),
      }, schema: "github.projects.v0.ProjectCardMove")
    end
  end

  context "track_deletion" do
    test "tracks card metrics before deletion" do
      card = create :project_card
      card.expects(:track_deletion)
      card.destroy
    end

    test "sends metrics to DataDog" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      Timecop.freeze(5.days.ago) do
        @note = create(:project_card, note: "hooray")
        @issue = create :project_card
        @issue.archive
      end

      card_age = 2
      Timecop.freeze(@note.created_at + card_age.days) do
        @note.destroy
        @issue.destroy
      end

      increments = GitHub.dogstats.increments("projects.card_deleted")
      note_tags = increments.first.tags.to_a
      issue_tags = increments.second.tags.to_a

      assert_equal 2, increments.length
      assert_equal "content_type:note", note_tags.first
      assert_equal "is_archived:false", note_tags.second

      assert_equal "content_type:issue", issue_tags.first
      assert_equal "is_archived:true", issue_tags.second

      histograms = GitHub.dogstats.histograms("projects.card_deleted_age")
      assert_equal [2, 2], histograms.map(&:value)
    end
  end

  context "readable_by?" do
    test "falls back to the viewer's project permission" do
      org = create(:organization, admin: @owner)
      project = create(:project, owner: org)
      project.update_org_permission(nil)
      card = create(:project_card, project: project)

      read_user = create(:user)
      org.add_member(read_user)
      project.update_user_permission(read_user, :read)

      assert card.readable_by?(@owner)
      assert card.readable_by?(read_user)
      refute card.readable_by?(nil)
    end

    test "does not care about content redaction" do
      org = create(:organization, admin: @owner)
      project = create(:project, owner: org)
      card = create(:project_card, project: project)

      no_repo_access_user = create(:user)
      org.add_member(no_repo_access_user)
      repo = org.repositories.first
      repo.disassociate_member(no_repo_access_user, @owner)

      assert card.readable_by?(@owner)
      assert card.readable_by?(no_repo_access_user)
    end
  end
end
