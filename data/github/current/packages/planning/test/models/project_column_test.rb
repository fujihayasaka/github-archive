# typed: true
# frozen_string_literal: true

require "test_helper"

class MockProjectColumnForCollisionTesting
  include Kernel
  extend Forwardable

  def_delegators :@column, :prioritize_card!

  sig { params(column: ProjectColumn).void }
  def initialize(column)
    @column = column
  end

  def prioritize_dependent!(*args)
    @runs ||= 0

    if @runs < 1
      @runs += 1
      raise ActiveRecord::RecordNotUnique.new("Error on run #{@runs}")
    else
      @column.prioritize_dependent!(*T.unsafe(args))
    end
  end
end

class ProjectColumnTest < GitHub::TestCase
  include PrioritizationHelpers
  include StringFromBinaryTestHelper

  fixtures do
    @owner = create(:user)
    GitHub.context.push(actor_id: @owner.id)
    @repo = create(:public_repository, owner: @owner)
    @project = create(:project, owner: @repo)
    @column = create(:project_column, project: @project)
  end

  setup do
    GitHub.context.push(actor_id: @owner.id)
  end

  test "correctly returns no cards when issues are disabled, but does return them after enabling" do
    @org = create(:organization, admin: @owner, login: "the-org")
    private_repo = create(:private_repository, owner: @org, has_issues: false)
    issue = create(:issue, title: "this is a private org issue", repository: private_repo)
    issue_card = create(:project_card, content: issue, column: @column)

    assert_equal [], @column.cards_ids_without_disabled_repo_issues(@column.cards.not_archived.by_priority)
    assert_equal 0, @column.cards_count_project_column_view

    private_repo.update(has_issues: true)
    assert_equal [issue_card.id], @column.cards_ids_without_disabled_repo_issues(@column.cards.not_archived.by_priority)
    assert_equal 1, @column.cards_count_project_column_view
  end

  test "correctly returns cards excluding archived" do
    @org = create(:organization, admin: @owner, login: "the-org")
    private_repo = create(:private_repository, owner: @org, has_issues: false)
    issue = create(:issue, title: "this is a private org issue", repository: private_repo)
    another_issue = create(:issue, title: "this is another private org issue", repository: private_repo)
    create(:project_card, content: issue, column: @column)
    another_issue_card = create(:project_card, content: another_issue, column: @column)

    assert_equal 0, @column.cards_count_project_column_view

    private_repo.update(has_issues: true)
    assert_equal 2, @column.cards_count_project_column_view

    another_issue_card.archive
    assert_equal 1, @column.cards_count_project_column_view
  end

  test "gets a position" do
    assert_equal 0, @column.position
    next_column = create(:project_column, project: @project)
    assert_equal 1, next_column.position
  end

  test "can prioritize note-only cards" do
    allow_transaction_nesting do
      card_1 = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Irrelevant" })
      card_2 = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Irrelevant" })
      card_3 = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Irrelevant" })

      assert_equal [card_3, card_2, card_1].map(&:reload),
        @column.cards.by_priority

      @column.prioritize_card!(card_3, after: card_1)
      assert_equal [card_2, card_1, card_3].map(&:reload),
        @column.cards.by_priority

      @column.prioritize_card!(card_2, after: card_1)
      assert_equal [card_1, card_2, card_3].map(&:reload),
        @column.cards.by_priority
    end
  end

  test "can't exceed project max columns" do
    project = create(:project)

    Project.stub_const(:MAX_COLUMNS, 2) do
      2.times { create(:project_column, project: project) }
      column = build(:project_column, project: project)
      refute column.save
      assert_predicate column.errors[:max_columns], :present?
    end
  end

  test "can save column in project with max number of columns" do
    project = create(:project)

    Project.stub_const(:MAX_COLUMNS, 2) do
      col1 = create(:project_column, project: project)
      col2 = create(:project_column, project: project)

      col1.name = "Something New"
      assert col1.save!
    end
  end

  test "destroying a column destroys its cards" do
    card_id = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Irrelevant" }).id
    only = [AddToSearchIndexJob, DestroyDependentRecordsJob, RemoveFromSearchIndexJob]
    perform_enqueued_jobs(only: only) { @column.destroy }

    assert_nil ProjectCard.find_by(id: card_id)
  end

  context "prioritize_card!" do
    test "works with :after" do
      card_1 = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Irrelevant" })
      card_2 = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Irrelevant" })
      card_3 = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Irrelevant" })

      assert_equal [card_3, card_2, card_1], @column.ordered_cards_for(@owner)

      allow_transaction_nesting { @column.prioritize_card!(card_3, after: card_1) }
      @column.cards.reload
      assert_equal [card_2, card_1, card_3], @column.ordered_cards_for(@owner)
    end

    test "puts card at top when after has been removed" do
      card_1 = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Irrelevant" })
      card_2 = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Irrelevant" })
      card_2.destroy

      allow_transaction_nesting { @column.prioritize_card!(card_1, after: card_2) }
      assert_equal [card_1], @column.ordered_cards_for(@owner)
    end

    test "can move card from one column to another" do
      card_1 = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Irrelevant" })
      card_2 = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Irrelevant" })
      column_2 = create(:project_column, project: @project)

      allow_transaction_nesting { column_2.prioritize_card!(card_1) }

      assert_equal [card_1], column_2.ordered_cards_for(@owner)
      assert_equal [card_2], @column.ordered_cards_for(@owner)
    end

    test "can move card from one column to another, using :after" do
      card_1 = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Irrelevant" })
      card_2 = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Irrelevant" })

      column_2 = create(:project_column, project: @project)
      card_3 = ProjectCard.create_in_column(column_2, creator: @owner, content_params: { content_type: "Note", note: "Irrelevant" })

      column_2.prioritize_card!(card_3)

      allow_transaction_nesting { column_2.prioritize_card!(card_1, after: card_3) }

      assert_equal [card_3, card_1], column_2.ordered_cards_for(@owner)
      assert_equal [card_2], @column.ordered_cards_for(@owner)
    end

    test "can prioritize to the top when the column contains an archived card" do
      card_1 = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Card 1" })
      card_2 = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Card 2" })
      card_3 = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Card 3" })
      archived_card = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Archived" })
      archived_card.archive

      assert_equal [card_3, card_2, card_1], @column.ordered_cards_for(@owner)

      allow_transaction_nesting { @column.prioritize_card!(card_1) }
      @column.cards.reload

      assert_equal [card_1, card_3, card_2], @column.ordered_cards_for(@owner)
    end

    test "can prioritize to the middle when the column contains an archived card" do
      card_1 = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Card 1" })
      card_2 = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Card 2" })
      card_3 = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Card 3" })
      archived_card = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Archived" })
      archived_card.archive

      assert_equal [card_3, card_2, card_1], @column.ordered_cards_for(@owner)

      allow_transaction_nesting { @column.prioritize_card!(card_3, after: card_2) }
      @column.cards.reload

      assert_equal [card_2, card_3, card_1], @column.ordered_cards_for(@owner)
    end

    test "can prioritize to the bottom when the column contains an archived card" do
      card_1 = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Card 1" })
      card_2 = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Card 2" })
      card_3 = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Card 3" })
      archived_card = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Archived" })
      archived_card.archive

      assert_equal [card_3, card_2, card_1], @column.ordered_cards_for(@owner)

      allow_transaction_nesting { @column.prioritize_card!(card_3, after: card_1) }
      @column.cards.reload

      assert_equal [card_2, card_1, card_3], @column.ordered_cards_for(@owner)
    end

    test "handles collision" do
      unsaved_card = build(:note_project_card, column: @column, note: "irrelevant")
      saved_card = MockProjectColumnForCollisionTesting.new(@column).prioritize_card!(unsaved_card)

      assert_predicate saved_card, :persisted?
      refute_nil saved_card.priority
      assert_includes @column.ordered_cards_for(@owner), saved_card
    end

    test "triggers project card move events" do
      card = create(:project_card, column: @column, creator: @owner)
      done_column = create(:project_column, project: @project)

      card.expects(:trigger_moved_event)

      done_column.prioritize_card!(card)
    end

    test "stops trying to set priority after too many collisions" do
      @column.stubs(:prioritize_dependent!).raises(ActiveRecord::RecordNotUnique.new("Expected collision error"))

      unsaved_card = build(:note_project_card, column: @column, note: "irrelevant")
      saved_card = @column.prioritize_card!(unsaved_card)

      assert_predicate saved_card, :persisted?
      assert_nil saved_card.priority
      assert_includes @column.cards, saved_card
    end

    test "translates ActiveRecord::StatementInvalid to InvalidSqlStatement" do
      @column.stubs(:prioritize_dependent!).raises(ActiveRecord::StatementInvalid.new("boom"))

      unsaved_card = build(:note_project_card, column: @column, note: "irrelevant")
      @column.prioritize_card!(unsaved_card)

      assert_includes Failbot.reports.map { |r| Failbot.exception_classname_from_hash(r) }, "ProjectColumn::LegacySortingOverridesDependency::InvalidSqlStatementError"
    end

    test "traces prioritize_dependent! execution" do
      project = create(:project, owner: @repo)
      column = create(:project_column, project: project)
      unsaved_card = build(:note_project_card, column: @column, note: "irrelevant")

      exporter.reset
      assert column.prioritize_dependent!(unsaved_card, position: :top)

      span = find_span_by(name: "project_column#prioritize_dependent!")

      refute_nil span
      assert_equal column.id, span.attributes["context_id"]
      assert_equal column.class.name, span.attributes["context_type"]
    end

    test "raises an error if called while locked for rebalancing" do
      card = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Irrelevant" })
      @column.lock_for_rebalance do
        assert_raises(GitHub::Prioritizable::Context::LockedForRebalance) do
          @column.prioritize_card!(card)
        end
      end
    end

    test "raises an error if called on an archived card" do
      card = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Irrelevant" })
      card.archive

      assert_raises(ProjectColumn::LegacySortingOverridesDependency::PrioritizingArchivedCardError) do
        @column.prioritize_card!(card)
      end

      card.reload

      assert_predicate card, :archived?
    end

    test "raises an error if called on an unprioritized after_card" do
      card_1 = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Irrelevant" })
      card_2 = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Irrelevant" })
      card_2.archive

      assert_raises(ProjectColumn::LegacySortingOverridesDependency::InvalidPrioritizationTargetError) do
        @column.prioritize_card!(card_1, after: card_2)
      end
    end

    test "does not move the card if the target column exceeds the max" do
      move_to_column = create(:project_column, project: @project)
      move_card = create(:project_card, column: @column, note: "YUP")
      create(:project_card, column: move_to_column, note: "staying put")

      ProjectColumn.stub_const(:MAX_CARDS, 1) do
        old_priority = move_card.priority
        old_column = move_card.column
        card_after_move = move_to_column.prioritize_card!(move_card)

        assert_equal old_priority, card_after_move.priority
        assert_equal old_column, card_after_move.column
      end
    end
  end

  context "ordered_cards" do
    test "returns cards in order" do
      card_1 = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Irrelevant" })
      card_2 = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Irrelevant" })
      card_3 = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Note", note: "Irrelevant" })

      assert_equal [card_3, card_2, card_1], @column.cards.by_priority

      allow_transaction_nesting do
        @column.prioritize_card!(card_1)
        @column.prioritize_card!(card_3, after: card_1)
        @column.prioritize_card!(card_2, after: card_1)
      end
      assert_equal [card_1, card_2, card_3], @column.ordered_cards_for(@owner)
    end
  end

  context "ordered_cards_for" do
    test "prefills issue associations" do
      issue = create(:issue, repository: @repo)
      card = ProjectCard.create_in_column(@column, creator: @owner, content_params: { content_type: "Issue", content_id: issue.id })
      card = @column.ordered_cards_for(@owner).first

      assert_equal issue, card.content
      assert card.content.association(:assignees).loaded?, "didn't load assignees"
      assert card.content.association(:labels).loaded?, "didn't load labels"
      assert card.content.association(:user).loaded?, "didn't load user"
    end

    test "does not expose things a user can't see" do
      org = create(:organization)
      visible_repo = create(:public_repository, owner: org)
      visible_issue = create(:issue, repository: visible_repo)
      visible_card = create(:project_card, column: @column, content: visible_issue)

      not_visible_repo = create(:private_repository, owner: org)
      not_visible_issue = create(:issue, repository: not_visible_repo)
      not_visible_card = create(:project_card, column: @column, content: not_visible_issue)

      @column.prioritize_card! visible_card
      @column.prioritize_card! not_visible_card, after: visible_card

      viewer = create(:user)
      visible_repo.add_member(viewer)

      visible, redacted = @column.ordered_cards_for(viewer)

      assert_equal visible_issue, visible.content

      assert_nil redacted.content
      assert_equal "Redacted", redacted.content_type
      assert_equal ProjectCardRedactor::RedactedCard::INSUFFICIENT_PERMISSION, redacted.reason_for_redaction
    end

    test "does not expose content in deleted repositories" do
      org = create(:organization)
      visible_repo = create(:public_repository, owner: org)
      visible_issue = create(:issue, repository: visible_repo)
      visible_card = create(:project_card, column: @column, content: visible_issue)

      not_visible_repo = create(:public_repository, owner: org)
      not_visible_issue = create(:issue, repository: not_visible_repo)
      not_visible_card = create(:project_card, column: @column, content: not_visible_issue)

      @column.prioritize_card! visible_card
      @column.prioritize_card! not_visible_card, after: visible_card

      viewer = create(:user)
      visible_repo.add_member(viewer)

      not_visible_repo.destroy
      visible, redacted = @column.ordered_cards_for(viewer)

      assert_equal visible_issue, visible.content

      assert_nil redacted.content
      assert_equal "Redacted", redacted.content_type
      assert_equal ProjectCardRedactor::RedactedCard::REPOSITORY_MISSING, redacted.reason_for_redaction
    end

    test "does not expose spammy content to a user" do
      org = create(:organization)
      visible_repo = create(:public_repository, owner: org)
      visible_issue = create(:issue, repository: visible_repo)
      visible_card = create(:project_card, column: @column, content: visible_issue)

      spammer = create(:user, login: "spammer", spammy: true)
      spammy_issue = create(:issue, repository: visible_repo, user: spammer, title: "DEALS DEALS DEALS")
      spammy_card = create(:project_card, column: @column, content: spammy_issue)

      @column.prioritize_card! visible_card
      @column.prioritize_card! spammy_card, after: visible_card

      viewer = create(:user)
      visible_repo.add_member(viewer)

      visible, redacted = @column.ordered_cards_for(viewer)

      assert_equal visible_issue, visible.content

      assert_nil redacted.content
      assert_equal "Redacted", redacted.content_type
      assert_equal ProjectCardRedactor::RedactedCard::SPAMMY_CONTENT, redacted.reason_for_redaction
    end unless GitHub.enterprise?
  end

  context "instrumentation" do
    test "instruments project column creation" do
      events = subscribe "project_column.create"
      column = create(:project_column, project: @project)

      expected_payload = {
        project: @project.name,
        project_id: @project.id,
        project_column: column.name,
        project_column_id: column.id,
        actor: @owner.login,
        actor_id: @owner.id,
        rank: 2,
      }

      assert event = events.pop, "an event was expected"
      assert_equal "project_column.create", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments project column update" do
      events = subscribe "project_column.update"
      column = create(:project_column, project: @project)
      column.update_attribute(:name, "All the cool cards go here")

      assert event = events.pop, "an event was expected"
      assert_equal "project_column.update", event.name
      refute_nil event.payload[:changes]
      assert_equal "All the cool cards go here", event.payload[:changes][:name]
    end

    test "does not instrument project column update when no change and emoji in name" do
      string_containing_emoji = "This project is great! #{GRIN_EMOJI * 5}"
      events = subscribe "project_column.update"
      column = create(:project_column, project: @project, name: string_containing_emoji)
      column.update_attribute(:name, string_containing_emoji)

      event = events.pop
      assert_nil event
    end

    test "supports emoji for name" do
      column = create(:project_column, name: "we ❤️ emojis")

      assert_multibyte_tracked_changes(column, :name)
    end

    test "instruments project column move" do
      events = subscribe "project_column.move"
      column_1 = create(:project_column, name: "column one", project: @project)
      column_2 = create(:project_column, name: "column two", project: @project)
      @project.move_column(column_1, after: column_2)

      assert event = events.pop, "an event was expected"
      assert_equal "project_column.move", event.name
      assert_equal column_2.id, event.payload[:after_id]
    end

    test "instruments project column destroy" do
      events = subscribe "project_column.delete"
      column = create(:project_column, project: @project)

      expected_payload = {
        project: @project.name,
        project_id: @project.id,
        project_column: column.name,
        project_column_id: column.id,
        actor: @owner.login,
        actor_id: @owner.id,
        rank: 2,
      }
      perform_enqueued_jobs(only: [AddToSearchIndexJob]) { column.destroy }

      assert event = events.pop, "an event was expected"
      assert_equal "project_column.delete", event.name
      assert_equal expected_payload, event.payload
    end
  end

  context "validation" do
    test "setting a purpose not in the PURPOSES list causes validation failure" do
      @column.purpose = "xyzzy"
      refute_predicate @column, :valid?
    end

    test "setting a purpose that is in the PURPOSES list does not cause validation failure" do
      @column.purpose = "todo"
      assert_predicate @column, :valid?
    end

    test "setting a nil purpose does not cause validation failure" do
      @column.purpose = nil
      assert_predicate @column, :valid?
    end
  end

  context "archive_all_cards" do
    test "locks the project" do
      @column.archive_all_cards(actor: @owner)
      assert @column.project.locked_for?(Project::ProjectLock::CARD_ARCHIVING)
    end

    test "enqueues a background job" do
      current_time = Time.current

      Timecop.freeze(current_time) do
        assert_enqueued_with(
          job: ArchiveAllCardsInProjectColumnJob,
          args: [@column.id, { queued_at: current_time.to_s }],
        ) do
          @column.archive_all_cards(actor: @owner)
        end
      end
    end

    test "does not enqueue a job for readonly users" do
      user = preview_user
      assert_no_enqueued_jobs do
        @column.archive_all_cards(actor: user)
      end
    end
  end

  context "archive_all_cards_in_batches!" do
    test "raises an error if the project is unlocked" do
      assert_raises Project::CardArchivingLockRequired do
        @column.archive_all_cards_in_batches!
      end
    end

    test "does not attempt to re-archive archived cards" do
      archived_card = create(:project_card, column: @column, archived_at: 2.days.ago)
      card = create(:project_card, column: @column)
      timestamp = (Time.current + 1.second).to_s
      @column.project.lock!(lock_type: Project::ProjectLock::CARD_ARCHIVING, actor: @owner)

      archived_card.expects(:archive).never

      @column.archive_all_cards_in_batches! timestamp: timestamp
      card.reload

      assert card.archived?
    end

    test "sends card metrics to DataDog" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      create(:project_card, column: @column)
      timestamp = (Time.current + 1.second).to_s

      @column.project.lock!(lock_type: Project::ProjectLock::CARD_ARCHIVING, actor: @owner)
      @column.archive_all_cards_in_batches! timestamp: timestamp

      assert_equal [1], GitHub.dogstats.histograms("projects.archive_all_cards_count").map(&:value)
    end

    test "archives all cards in the column" do
      card = create(:project_card, column: @column)
      timestamp = (Time.current + 1.second).to_s

      @column.project.lock!(lock_type: Project::ProjectLock::CARD_ARCHIVING, actor: @owner)
      @column.archive_all_cards_in_batches! timestamp: timestamp

      card.reload
      assert card.archived?
    end

    test "returns false if there are no cards to archive" do
      @column.project.lock!(lock_type: Project::ProjectLock::CARD_ARCHIVING, actor: @owner)
      result = @column.archive_all_cards_in_batches! timestamp: Time.current
      assert_equal false, result
    end

    test "returns `false` if a single batch was fully processed" do
      create(:project_card, id: 1, column: @column)
      create(:project_card, id: 2, column: @column)
      create(:project_card, id: 3, column: @column)

      timestamp = (Time.current + 1.second).to_s

      @column.project.lock!(lock_type: Project::ProjectLock::CARD_ARCHIVING, actor: @owner)
      result = @column.archive_all_cards_in_batches! timestamp: timestamp

      assert_equal false, result
    end

    test "returns last id if there are more cards to be processed" do
      create(:project_card, id: 1, column: @column)
      create(:project_card, id: 2, column: @column)
      create(:project_card, id: 3, column: @column)

      timestamp = (Time.current + 1.second).to_s

      @column.project.lock!(lock_type: Project::ProjectLock::CARD_ARCHIVING, actor: @owner)
      result = @column.archive_all_cards_in_batches! timestamp: timestamp, batch_size: 2

      assert_equal 2, result
    end

    test "archive all cards in consecutive calls" do
      create(:project_card, id: 1, column: @column)
      create(:project_card, id: 2, column: @column)
      create(:project_card, id: 3, column: @column)
      card = create(:project_card, id: 4, column: @column)

      timestamp = (Time.current + 1.second).to_s
      run_next_batch = T.let(0, T.any(T::Boolean, Integer))

      @column.project.lock!(lock_type: Project::ProjectLock::CARD_ARCHIVING, actor: @owner)
      while run_next_batch
        run_next_batch = @column.archive_all_cards_in_batches! timestamp: timestamp, from_id: run_next_batch, batch_size: 2
      end

      card.reload
      assert card.archived?
      assert_equal false, run_next_batch
    end
  end

  context "automated_with_done_triggers?" do

    test "returns true with a done trigger" do
      workflow = create(:project_workflow, trigger_type: ProjectWorkflow::DONE_TRIGGERS.first, project: @project)
      workflow.set_transition_action(column: @column, creator: @owner)

      assert_equal true, @column.automated_with_done_triggers?
    end

    test "returns true when only one trigger is a done trigger" do
      done_workflow = create(:project_workflow, trigger_type: ProjectWorkflow::DONE_TRIGGERS.first, project: @project)
      done_workflow.set_transition_action(column: @column, creator: @owner)

      pending_workflow = create(:project_workflow, trigger_type: ProjectWorkflow::PENDING_CARD_TRIGGERS.first, project: @project)
      pending_workflow.set_transition_action(column: @column, creator: @owner)

      assert_equal true, @column.automated_with_done_triggers?
    end

    test "returns false when no done triggers" do
      assert_equal false, @column.automated_with_done_triggers?

      pending_workflow = create(:project_workflow, trigger_type: ProjectWorkflow::PENDING_CARD_TRIGGERS.first, project: @project)
      pending_workflow.set_transition_action(column: @column, creator: @owner)

      assert_equal false, @column.reload.automated_with_done_triggers?
    end

  end
end
