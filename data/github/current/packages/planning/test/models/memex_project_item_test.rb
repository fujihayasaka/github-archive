# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectItemTest < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers
  include GitHub::PullRequestTestHelpers
  include IssuesGraphTestHelpers

  fixtures do
    @memex = create(:memex_project)
    @item = create(:memex_project_item, memex_project: @memex)
    @text_column = create(
      :memex_project_column,
      user_defined: true,
      data_type: :text,
      memex_project: @memex
    )
    @single_select_column = create(:single_select_memex_column, memex_project: @memex)
    @single_select_options = @single_select_column.settings["options"]
    @iteration_column = create(:iteration_memex_column, memex_project: @memex)
    @iteration_options = @iteration_column.settings.dig("configuration", "iterations")
    @number_column = create(
      :memex_project_column,
      user_defined: true,
      data_type: :number,
      memex_project: @memex
    )
    @date_column = create(
      :memex_project_column,
      user_defined: true,
      data_type: :date,
      memex_project: @memex
    )

    @user  = create(:user)
    @repo  = create(:public_repository, owner: @user)
    @issue = create(:issue, user: @user, repository: @repo)
    @pull  = make_pr_and_repos

    @draft_item = build(:memex_project_item, memex_project: @memex, priority: 1)
    @draft_item.content = @draft_item.build_draft_issue(title: Faker::Lorem.unique.word)
    @draft_item.save!
  end

  setup do
    GitHub.flipper[:issues_graph_api].disable
    GitHub.flipper[:memex_increased_issues_graph_timeouts].disable

    # known as in: grouping has been acknowledged for these data types.  We are duplicating the list
    # here to ensure future additions/modifications to column data types take grouping into consideration.
    # The value(s) here are represent whether or not the data type is groupable.
    @known_ungroupable_data_types = %w[labels title linked_pull_requests reviewers tracks tracked_by parent_issue sub_issues_progress]
    @known_groupable_data_types   = %w[assignees date number iteration milestone repository single_select text issue_type]
  end

  context "validations" do
    test "requires content" do
      memex_item = build(:memex_project_item, content: nil)

      refute memex_item.save
      assert_includes memex_item.errors.full_messages, "Content can't be blank"
    end

    test "requires content_type to be one of allowed types" do
      memex_item = build(:memex_project_item, content: create(:milestone))

      refute memex_item.save
      assert_includes memex_item.errors.full_messages, "Content type is not included in the list"
    end

    test "requires content to be unique in the project" do
      new_memex_item = build(:memex_project_item, memex_project: @memex, content: @item.content)
      refute new_memex_item.save
      assert_includes new_memex_item.errors.full_messages, "Content already exists in this project"
    end

    test "requires content type for issue items" do
      content = create(:issue)
      memex_item = build(:memex_project_item, content: content)
      content_type = memex_item.content_type

      # skip before validation
      memex_item.content_type = nil

      refute memex_item.save
      assert_includes memex_item.errors.full_messages, "Content can't be blank"

      memex_item.content_type = content_type
      assert memex_item.save

      memex_item.content_type = nil
      refute memex_item.save
    end

    test "requires content type for pull request items" do
      content = create(:pull_request, :disable_disk_access)
      memex_item = build(:memex_project_item, content: content, repository: nil)
      content_type = memex_item.content_type

      # skip before validation
      memex_item.content_type = nil

      refute memex_item.save
      assert_includes memex_item.errors.full_messages, "Content can't be blank"

      memex_item.content_type = content_type
      assert memex_item.save

      memex_item.content_type = nil
      refute memex_item.save
    end

    test "does not require repository for draft issues" do
      content = create(:draft_issue)
      memex_item = build(:memex_project_item, content: content, repository: nil)

      assert memex_item.save
    end

    test "sets denormalized issue fields on validation for an open issue item" do
      content = create(:issue)
      item = build(:memex_project_item, content: content, issue_id: nil)

      assert item.save
      assert_equal content.id, item.reload.issue_id
      assert_equal content.created_at, item.issue_created_at
      assert_nil item.issue_closed_at
      assert_equal content.state, item.state
      assert_nil item.state_reason
    end

    test "sets denormalized issue fields on validation for closed issue item" do
      content = create(:issue, state: "closed", state_reason: :not_planned)
      item = build(:memex_project_item, content: content, issue_id: nil)

      assert item.save
      assert_equal content.id, item.reload.issue_id
      assert_equal content.created_at, item.issue_created_at
      assert_equal content.closed_at, item.issue_closed_at
      assert_equal content.state, item.state
      assert_equal content.state_reason, item.state_reason
    end

    test "sets denormalized issue fields on validation for an open pull request item" do
      content = create(:pull_request, :disable_disk_access)
      item = build(:memex_project_item, content: content, issue_id: nil)

      assert item.save

      item.reload
      issue = content.issue

      assert_equal issue.id, item.reload.issue_id
      assert_equal issue.created_at, item.issue_created_at
      assert_nil item.issue_closed_at
      assert_equal issue.state, item.state
      assert_nil item.state_reason
    end

    test "sets denormalized issue fields on validation for a merged pull request item" do
      content = create(:pull_request, :merged, :disable_disk_access)
      item = build(:memex_project_item, content: content, issue_id: nil)

      issue = content.issue

      assert item.save
      assert_equal issue.id, item.reload.issue_id
      assert_equal issue.created_at, item.issue_created_at
      assert_equal issue.closed_at, item.issue_closed_at
      assert_equal issue.state, item.state
      assert_nil item.state_reason
    end

    test "does not require an denormalized issue fields for a draft issue item" do
      content = create(:draft_issue)
      item = build(:memex_project_item, content: content, issue: nil)
      assert item.save
      assert_nil item.reload.issue_id
      assert_nil item.issue_created_at
      assert_nil item.issue_closed_at
      assert_nil item.state
      assert_nil item.state_reason
    end

    test "allows priority to be set explicitly to nil" do
      assert build(:memex_project_item, priority: nil).valid?
    end

    test "requires priority to be a non-negative integer if non-nil" do
      memex_item = build(:memex_project_item, priority: -1)

      refute memex_item.save
      assert_includes memex_item.errors.full_messages, "Priority must be greater than or equal to 0"
    end

    test "requires priority to be less than max allowed value" do
      memex_item = build(:memex_project_item, priority: GitHub::Prioritizable::MAX_PRIORITY_VALUE + 1)

      refute memex_item.save
      assert_includes memex_item.errors.full_messages, "Priority must be less than or equal to #{GitHub::Prioritizable::MAX_PRIORITY_VALUE}"
    end

    test "requires priority to be unique in the project" do
      existing_memex_item = create(:memex_project_item, priority: 1)
      new_memex_item = build(:memex_project_item, memex_project: existing_memex_item.memex_project, priority: 1)

      refute new_memex_item.save
      assert_includes new_memex_item.errors.full_messages, "Priority has already been taken"
    end

    test "requires a memex project" do
      memex_item = build(:memex_project_item, memex_project: nil)

      refute memex_item.save
      assert_includes memex_item.errors.full_messages, "Memex project can't be blank"
    end

    test "requires a creator" do
      memex_item = build(:memex_project_item, creator: nil)

      refute memex_item.save
      assert_includes memex_item.errors.full_messages, "Creator can't be blank"
    end

    test "issue_type avoids issue model batch_method" do
      GitHub.flipper[:issue_types].enable
      organization = create(:organization)
      issue_type = organization.issue_types.find_by!(name: IssueType::DEFAULTS.first[:name])
      memex_project = create(:memex_project, owner: organization)
      repository = create(:repository, owner: organization)
      issue = create(:issue, repository: repository, issue_type: issue_type)
      memex_project_item = create(:memex_project_item, memex_project: memex_project, content: issue)
      issue_type.update!(enabled: false)

      refute_predicate issue_type, :enabled?, "Expected issue type to not be enabled"
      assert_nil memex_project_item.content.issue_type, "Expected issue type to not be accessible as its disabled"
      assert_equal issue_type, memex_project_item.issue_type, "Expected issue type to be accessible"
    end

    test "requires the creator to have a verified email" do
      # the email suffix `+forceverify@github.com` forces the email verification validation.
      memex_item = build(:memex_project_item, creator: create(:user, email: "user+forceverify@github.com"))
      refute memex_item.creator.emails.verified.any?

      refute memex_item.save
      assert_includes memex_item.errors.full_messages, "Creator must have a verified email address"
    end unless GitHub.enterprise?

    test "does not require the creator to have a verified email within Enterprise", enterprise_only: true do
      memex_item = build(:memex_project_item, creator: create(:user, email: "user+forceverify@github.com"))
      refute memex_item.creator.emails.verified.any?

      assert memex_item.save
    end

    test "rejects a memex item from being created when the memex project hits the limit per page" do
      # allow at most another item from current count
      fake_limit = @memex.memex_project_items.count + 1

      MemexProjectItem.stub_const(memex_item_limit_constant(@memex), fake_limit) do
        item = build(:memex_project_item, memex_project: @memex, content: create(:issue))
        assert item.save

        item_past_limit = build(:memex_project_item, memex_project: @memex, content: create(:draft_issue))
        refute item_past_limit.save
        assert_includes item_past_limit.errors.full_messages, "Projects cannot have more than #{fake_limit} items. To add more, please archive or delete existing items."

        assert @memex.memex_project_items.count == fake_limit
      end
    end

    if GitHub.spamminess_check_enabled?
      test "does not include user hidden content when enforcing memex item limit" do
        # allow at most another item from current count
        fake_limit = @memex.memex_project_items.count + 1

        spammy_user = create(:verified_user, spammy: true)
        spammy_user.emails.first.verify!

        # Create the spammy content that won't be considered when enforcing page limit
        spammy_item = create(:memex_project_item, memex_project: @memex, creator: spammy_user)
        assert_predicate spammy_item, :user_hidden?

        MemexProjectItem.stub_const(:PER_PAGE_LIMIT, fake_limit) do
          assert @memex.memex_project_items.count == fake_limit

          item = build(:memex_project_item, memex_project: @memex, content: create(:issue))
          assert item.save

          assert @memex.memex_project_items.count > fake_limit
        end
      end
    end
  end

  context "#update_priority" do
    test "passes arguments correctly to memex_project#save_with_priority" do
      item = create(:memex_project_item, memex_project: @memex)
      @memex.expects(:save_with_priority!).with(item, position: :top, suppress_hydro_events: true).returns(true)
      item.update_priority({ position: :top }, suppress_hydro_events: true)
    end
  end

  context "#update_column_values" do
    test "it supports multiple column value updates and correctly passes arguments to item#set_column_value" do
      item = create(:memex_project_item, memex_project: @memex)
      column_1 = create(:memex_project_column, data_type: :text, memex_project: @memex)
      column_2 = create(:memex_project_column, data_type: :text, memex_project: @memex)

      column_value_updates = [
        {
          column: column_1,
          value: "value 1",
          append_only: false,
        },
        {
          column: column_2,
          value: "value 2",
          append_only: false,
        }
      ]

      column_value_updates.each do |column_value_update|
        item.expects(:set_column_value).with(
          column_value_update[:column],
          column_value_update[:value],
          @user,
          column_value_update[:append_only],
          suppress_hydro_events: true
        )
      end
      item.update_column_values(column_value_updates, @user, suppress_hydro_events: true)
    end

  end

  context "#to_hash" do
    test "dumps streamlined attributes of the object" do
      content = create(:issue)
      memex_item = create(:memex_project_item, priority: 1, priority_numerator: 1, priority_denominator: 2, content:)

      expected_hash = {
        id: memex_item.id,
        priority: 1,
        virtualPriority: "00000000.5",
        contentId: content.id,
        contentType: content.class.name,
        contentRepositoryId: content.repository_id,
        updatedAt: memex_item.updated_at,
        createdAt: memex_item.created_at,
        issueCreatedAt: content.created_at,
        state: content.state
      }

      assert_equal expected_hash, memex_item.reload.to_hash
    end

    test "handles no columns requested with the same data shape" do
      content = create(:issue)
      memex_item = create(:memex_project_item, priority: nil, content: content)

      expected_hash = {
        id: memex_item.id,
        priority: nil,
        virtualPriority: nil,
        contentId: content.id,
        contentType: content.class.name,
        contentRepositoryId: content.repository_id,
        updatedAt: memex_item.updated_at,
        createdAt: memex_item.created_at,
        issueCreatedAt: content.created_at,
        state: content.state
      }

      assert_equal expected_hash, memex_item.to_hash(columns: [])
    end

    test "includes requested column data" do
      content = create(:draft_issue)
      memex_item = create(:memex_project_item, priority: nil, content: content)

      expected_hash = {
        id: memex_item.id,
        priority: nil,
        virtualPriority: nil,
        contentId: content.id,
        contentType: content.class.name,
        contentRepositoryId: nil,
        content: { id: content.id },
        updatedAt: memex_item.updated_at,
        createdAt: memex_item.created_at,
        memexProjectColumnValues: [
          {
            memexProjectColumnId: "Title",
            value: { title: { raw: content.title, html: content.title } },
          }
        ]
      }

      assert_equal(
        expected_hash,
        memex_item.to_hash(columns: [MemexProjectColumn.default_column("Title")])
      )
    end

    test "includes url for an issue in `content` key when using prefilled_associations option" do
      issue = create(:issue)
      memex_item = create(:memex_project_item, :with_denormalized_title, priority: nil, content: issue)
      title_column = memex_item.memex_project.columns.find(&:title?)
      prefill_result = MemexProjectItemPrefiller.new(
        [memex_item],
        columns: [title_column],
        read_denormalized_title: true,
        title_column: title_column
      ).prefill
      refute_nil prefill_result

      expected_content_hash = {
        id: issue.id,
        url: issue.url
      }

      assert_equal(
        expected_content_hash,
        memex_item.to_hash(
          columns: [title_column],
          require_prefilled_associations: true,
          prefilled_associations: prefill_result
        )[:content]
      )
    end

    test "includes url for a pull request in `content` key when using prefilled_associations option" do
      pull = create(:pull_request, :disable_disk_access, repository: @repo, user: @user)
      memex_item = create(:memex_project_item, :with_denormalized_title, priority: nil, content: pull)
      title_column = memex_item.memex_project.columns.find(&:title?)
      prefill_result = MemexProjectItemPrefiller.new(
        [memex_item],
        columns: [title_column],
        read_denormalized_title: true,
        title_column: title_column
      ).prefill
      refute_nil prefill_result

      expected_content_hash = {
        id: pull.id,
        url: pull.url
      }

      assert_equal(
        expected_content_hash,
        memex_item.to_hash(
          columns: [title_column],
          require_prefilled_associations: true,
          prefilled_associations: prefill_result
        )[:content]
      )
    end

    test "excludes url for a draft issue from `content` key when using prefilled_associations option" do
      # This is because draft issues do not have their own URL yet.

      draft_issue = create(:draft_issue)
      memex_item = create(:memex_project_item, :with_denormalized_title, priority: nil, content: draft_issue)
      title_column = memex_item.memex_project.columns.find(&:title?)
      prefill_result = MemexProjectItemPrefiller.new(
        [memex_item],
        columns: [title_column],
        read_denormalized_title: true,
        title_column: title_column
      ).prefill
      refute_nil prefill_result

      expected_content_hash = { id: draft_issue.id }

      assert_equal(
        expected_content_hash,
        memex_item.to_hash(
          columns: [title_column],
          require_prefilled_associations: true,
          prefilled_associations: prefill_result
        )[:content]
      )
    end

    test "serializes a redacted item correctly when no columns are requested" do
      Timecop.freeze(2022, 4, 7, 0, 0, 0, 0) do
        now = Time.zone.now

        expected_hash = {
          id: @item.id,
          priority: @item.priority,
          virtualPriority: @item.virtual_priority,
          contentType: "RedactedItem",
          contentId: -1,
          contentRepositoryId: nil,
          updatedAt: now,
          createdAt: now,
        }

        assert_equal expected_hash, @item.redact!.to_hash
      end
    end

    test "serializes a redacted item correctly when the item is redacted" do
      Timecop.freeze(2022, 4, 7, 0, 0, 0, 0) do
        now = Time.zone.now
        archived_item = create(:memex_project_item, memex_project: @memex, archived_at: now, archiver: @user)

        expected_hash = {
          contentId: -1,
          contentType: "RedactedItem",
          contentRepositoryId: nil,
          id: archived_item.id,
          priority: archived_item.priority,
          virtualPriority: archived_item.virtual_priority,
          archived: {
            archivedAt: now,
            archivedBy: nil
          },
          updatedAt: now,
          createdAt: now,
        }

        archived_item.archive!

        assert_equal expected_hash, archived_item.reload.redact!.to_hash
      end
    end

    test "serializes a redacted item correctly when additional columns are requested" do
      Timecop.freeze(2022, 4, 7, 0, 0, 0, 0) do
        now = Time.zone.now

        expected_hash = {
          id: @item.id,
          priority: @item.priority,
          virtualPriority: @item.virtual_priority,
          contentId: -1,
          contentType: "RedactedItem",
          contentRepositoryId: nil,
          content: { id: -1 },
          updatedAt: now,
          createdAt: now,
          memexProjectColumnValues: [
            {
              memexProjectColumnId: "Title",
              value: { title: "You can't see this item" },
            }
          ]
        }

        actual_hash = @item
          .redact!
          .to_hash(columns: [MemexProjectColumn.default_column("Title")])

        assert_equal expected_hash, actual_hash
      end
    end

    test "serializes issueCreatedAt when an issue has a created_at " do
      Timecop.freeze(2023, 7, 21, 0, 0, 0, 0) do
        now = Time.zone.now
        content = create(:issue)
        memex_item = create(:memex_project_item, priority: nil, content: content, issue_created_at: now)
        title_column = memex_item.memex_project.columns.find(&:title?)

        assert_equal(
          Time.zone.now,
          memex_item.to_hash(
            columns: [title_column],
          )[:issueCreatedAt]
          )
      end
    end

    test "serializes issueClosedAt when an issue has a closed_at" do
      Timecop.freeze(2023, 7, 22, 0, 0, 0, 0) do
        now = Time.zone.now
        content = create(:issue, state: "closed", closed_at: now)
        memex_item = create(:memex_project_item, priority: nil, content: content)
        title_column = memex_item.memex_project.columns.find(&:title?)

        assert_equal(
          Time.zone.now,
          memex_item.to_hash(
            columns: [title_column],
          )[:issueClosedAt]
          )
      end
    end

    test "serializes state & stateReason when an issue has been closed w/ a reason" do
      Timecop.freeze(2023, 7, 22, 0, 0, 0, 0) do
        now = Time.zone.now
        content = create(:issue, state: "closed", state_reason: :not_planned, closed_at: now)
        memex_item = create(:memex_project_item, priority: nil, content: content)
        title_column = memex_item.memex_project.columns.find(&:title?)

        assert_equal(
          content.state,
          memex_item.to_hash(
            columns: [title_column],
          )[:state]
        )

        assert_equal(
          content.state_reason,
          memex_item.to_hash(
            columns: [title_column],
          )[:stateReason]
        )
      end
    end

    test "traces the behaviour of the column value methods" do
      item = create(:memex_project_item)

      item.to_hash(
        columns: item.memex_project.columns.find_all { |c| c.title? || c.status? },
        require_prefilled_associations: false
      )

      span = find_span_by(name: "memex_project_item#special_type_column_value")
      refute_nil span
      assert_equal "title", span.attributes["data_type"]
      assert_equal true, span.attributes["has_data"]

      span = find_span_by(name: "memex_project_item#generic_type_column_value")
      refute_nil span
      assert_equal "single_select", span.attributes["data_type"]
      assert_equal false, span.attributes["has_data"]
    end
  end

  context "#transfer_issue_item" do
    test "does not update a PullRequest item" do
      pull = create(:pull_request, :disable_disk_access)
      pull_item = create(:memex_project_item, memex_project: @memex, content: pull)
      issue = create(:issue)

      refute pull_item.transfer_issue_item(issue)
      assert_equal pull_item.reload.content, pull
    end

    test "does not update a DraftIssue item" do
      draft_issue = create(:draft_issue)
      draft_item = create(:memex_project_item, memex_project: @memex, content: draft_issue)
      issue = create(:issue)

      refute draft_item.transfer_issue_item(issue)
      assert_equal draft_item.reload.content, draft_issue
    end

    test "does not update an Issue item with a different owner" do
      issue = create(:issue, repository: @repo)
      issue_item = create(:memex_project_item, memex_project: @memex, content: issue)

      user = create(:user)
      repo_with_different_owner = create(:repository, owner: user)
      new_issue = create(:issue, repository: repo_with_different_owner)

      refute issue_item.transfer_issue_item(new_issue)
      assert_equal issue_item.reload.content, issue
    end

    test "updates the issue item content and denormalized column values" do
      milestone = create(:milestone, repository: @repo)
      issue = create(:issue, repository: @repo, milestone: milestone)
      issue_item = create(:memex_project_item, memex_project: @memex, content: issue)

      # When an issue is transferred, we want to remove the milestones associated with the issue, because they will no longer exist in the new repo
      milestone_column = issue_item.memex_project.find_column_by_name_or_id(MemexProjectColumn::MILESTONE_COLUMN_NAME)
      column_value = create(:milestone_column_value, memex_project_item: issue_item, memex_project_column: milestone_column, value: milestone.id, json_value: {
        type: "Milestone", value: milestone.memex_column_hash.stringify_keys
      })

      repo = create(:repository, owner: @memex.owner)
      new_issue = create(:issue, repository: repo)

      assert issue_item.transfer_issue_item(new_issue)
      assert_equal issue_item.reload.content, new_issue
      assert_memex_item_is_denormalized(issue_item.memex_project, new_issue, refute_repo_fields_are_denormalized: true)
    end
  end

  context "#replace_content" do
    test "converts a draft issue item to an issue item" do
      draft_issue = create(:draft_issue)
      item = create(:memex_project_item, memex_project: @memex, content: draft_issue, repository: nil)

      milestone = create(:milestone)
      issue = create(:issue, repository: milestone.repository, milestone: milestone)

      assert item.replace_content(issue, @user)
      item.reload

      assert_equal item.content_type, "Issue"
      assert_equal item.content_id, issue.id
      assert_equal item.repository_id, issue.repository.id
      # Should this account for milestones?
      assert_memex_item_is_denormalized(@memex, issue)
    end

    test "converts a draft issue item to a pull request item" do
      draft_issue = create(:draft_issue)
      item = create(:memex_project_item, memex_project: @memex, content: draft_issue, repository: nil)

      pull = create(:pull_request, :disable_disk_access)

      assert item.replace_content(pull, @user)
      item.reload

      assert_equal item.content_type, "PullRequest"
      assert_equal item.content_id, pull.id
      assert_equal item.repository_id, pull.repository.id
      assert_memex_item_is_denormalized(@memex, pull)
    end

    test "does not denormalize the title value when the item update fails" do
      issue = create(:issue)
      issue_item = create(:memex_project_item, memex_project: @memex, content: issue, repository: issue.repository)

      draft_issue = create(:draft_issue)
      draft_issue_item = create(:memex_project_item, memex_project: @memex, content: draft_issue, repository: nil)

      # We expect the update to fail because there is already an item for this issue in the project.
      refute draft_issue_item.replace_content(issue, @user)

      assert_equal draft_issue_item.reload.content, draft_issue
      # Should this account for milestones?
      refute_memex_item_is_denormalized(@memex, issue_item)
    end
  end

  context "column data type and #group_by_value orthogonality" do
    test "un-groupable data types will raise an error" do
      @known_ungroupable_data_types.each do |data_type|
        column = create(:memex_project_column, memex_project: @memex, data_type: data_type)

        assert_raises(ArgumentError, "#{data_type} did not raise error.") do
          @item.group_by_value(column, require_prefilled_associations: false)
        end
      end
    end

    test "groupable data types will not raise an error" do
      @known_groupable_data_types.each do |data_type|
        column = create(:memex_project_column, memex_project: @memex, data_type: data_type)

        assert_nothing_raised do
          @item.group_by_value(column, require_prefilled_associations: false)
        end
      end
    end

    test "all data types are accounted for" do
      unknown_data_types = MemexProjectColumn.data_types.keys - @known_groupable_data_types - @known_ungroupable_data_types

      assert_empty unknown_data_types, "Unknown data types: #{unknown_data_types}"
    end
  end

  context "#group_by_value" do
    test "returns assignees" do
      user_1 = create(:user, login: "foo")
      org    = create(:organization, login: "org", admin: user_1)
      user_2 = create(:user, login: "bar").tap { |u| org.add_member(u) }

      repo  = create(:repository, owner: org)
      issue = create(:issue, repository: repo, user: user_1)
      item  = create(:memex_project_item, content: issue)

      memex  = item.memex_project
      column = memex.find_column_by_name_or_id(MemexProjectColumn::ASSIGNEES_COLUMN_NAME)

      # Returns nil if no assignees
      assert_empty issue.assignees
      assert_nil item.group_by_value(column, require_prefilled_associations: false)

      # Returns login if single user
      assert item.set_column_value(column, [user_1.id], user_1)
      assert_equal %w[foo], item.reload.group_by_value(column, require_prefilled_associations: false)

      # Returns logins sorted and separated by commas if multiple users
      assert item.set_column_value(column, [user_1.id, user_2.id], user_1)
      assert_equal %w[bar foo], item.reload.group_by_value(column, require_prefilled_associations: false)
    end

    test "returns date" do
      date = Date.parse("2001-01-02")

      assert_nil @item.column_value(@date_column, require_prefilled_associations: false)

      assert @item.set_column_value(@date_column, date.to_s, @user)
      assert_equal date, @item.reload.group_by_value(@date_column, require_prefilled_associations: false)
    end

    test "returns iteration" do
      id = @iteration_options.first["id"]

      # Returns nil if item has no iteration
      assert @item.set_column_value(@iteration_column, nil, @user)
      assert_nil @item.reload.group_by_value(@iteration_column, require_prefilled_associations: false)

      # Returns iteration title if item has an iteration
      assert @item.set_column_value(@iteration_column, id, @user)
      assert_equal id, @item.reload.group_by_value(@iteration_column, require_prefilled_associations: false)
    end

    test "returns milestone" do
      issue = create(:issue)
      item = create(:memex_project_item, content: issue)
      milestone = create(:milestone, repository: issue.repository)
      milestone_column = item.memex_project.find_column_by_name_or_id(MemexProjectColumn::MILESTONE_COLUMN_NAME)

      # Returns nil if milestone is not set
      assert_nil item.group_by_value(milestone_column, require_prefilled_associations: false)

      # Returns milestone title if milestone is set
      assert item.set_column_value(milestone_column, milestone.id, @user)
      assert_equal milestone.title, item.reload.group_by_value(milestone_column, require_prefilled_associations: false)
    end

    test "returns issue_type" do
      org_admin = create(:verified_user)
      org = create(:organization, admin: org_admin)
      GitHub.flipper[:issue_types].enable(org)

      memex = create(:memex_project, owner: org)
      issue_type = create(:issue_type, owner: org, name: "test")
      issue_type_column = memex.find_column_by_name_or_id(MemexProjectColumn::TYPE_COLUMN_NAME)
      repository = create(:repository, owner: org)
      issue = create(:issue, repository: repository)
      item = create(:memex_project_item, memex_project: memex, content: issue)

      # Returns nil if issue_type is not set
      assert_nil item.group_by_value(issue_type_column, require_prefilled_associations: false)

      # Returns issue_type name if issue_type is set
      assert item.set_column_value(issue_type_column, issue_type.id, org_admin)
      assert_equal issue_type.name, item.reload.group_by_value(issue_type_column, require_prefilled_associations: false)
    end

    test "returns number" do
      number = 42

      column = create(:memex_project_column, memex_project: @memex, data_type: "number")

      assert_nil @item.group_by_value(column, require_prefilled_associations: false)

      assert @item.set_column_value(column, number, @user)
      assert_equal number, @item.reload.group_by_value(column, require_prefilled_associations: false)
    end

    test "returns repository" do
      repository_column = @memex.find_column_by_name_or_id(MemexProjectColumn::REPOSITORY_COLUMN_NAME)

      # draft issue has no repository
      draft_issue = create(:draft_issue, title: "github")
      item = create(:memex_project_item, content: draft_issue, memex_project: @memex)
      assert_nil item.reload.group_by_value(repository_column, require_prefilled_associations: false)

      # issue has a repository
      assert_equal @item.content.repository.name_with_owner, @item.group_by_value(repository_column, require_prefilled_associations: false)
    end

    test "returns single select" do
      # Returns nil if item has no single select option
      assert_nil @item.group_by_value(@single_select_column, require_prefilled_associations: false)

      # Returns the option name if item has a single select option
      single_select_option = @single_select_options.first
      assert @item.set_column_value(@single_select_column, single_select_option["id"], @user)

      value = @item.reload.group_by_value(@single_select_column, require_prefilled_associations: false)
      assert_equal single_select_option["id"], value
    end

    test "returns text" do
      assert_equal "", @item.group_by_value(@text_column, require_prefilled_associations: false)

      value = "foo"

      assert @item.set_column_value(@text_column, value, @user)
      assert_equal value, @item.reload.group_by_value(@text_column, require_prefilled_associations: false)
    end
  end

  context "#set_json_value" do
    test "updates an existing value" do
      title_column = @item.memex_project.find_column_by_name_or_id(MemexProjectColumn::TITLE_COLUMN_NAME)
      title_json = @item.denormalized_title_value
      title_json[:title][:raw] = "previous value"

      refute_equal @item.denormalized_title_value, title_json

      column_value = @item.memex_project_column_values.create(
        memex_project_column_id: title_column.id,
        value: @item.content.title,
        json_value: title_json,
        creator: @user,
      )

      assert column_value.persisted?
      assert @item.send(:set_json_value, title_column, @item.denormalized_title_value, @item.content.title, @user)
      assert_equal column_value.reload.json_value, @item.denormalized_title_value.with_indifferent_access
    end

    test "returns false when it fails to update an existing value" do
      title_column = @item.memex_project.find_column_by_name_or_id(MemexProjectColumn::TITLE_COLUMN_NAME)
      invalid_title_json = @item.denormalized_title_value
      invalid_title_json[:title][:raw] = ""

      refute_equal @item.denormalized_title_value, invalid_title_json

      column_value = @item.memex_project_column_values.create(
        memex_project_column_id: title_column.id,
        value: @item.content.title,
        json_value: @item.denormalized_title_value,
        creator: @user,
      )

      assert column_value.persisted?
      refute @item.send(:set_json_value, title_column, invalid_title_json, @item.content.title, @user)
      assert_equal column_value.reload.json_value, @item.denormalized_title_value.with_indifferent_access
      assert_equal ["Json value 'title' object must include a 'raw' value"], @item.errors.full_messages
    end

    test "builds and persists a value if one does not exist" do
      title_column = @item.memex_project.find_column_by_name_or_id(MemexProjectColumn::TITLE_COLUMN_NAME)

      refute @item.memex_project_column_values.find { |val| val.memex_project_column_id == title_column.id }

      assert @item.send(:set_json_value, title_column, @item.denormalized_title_value, @item.content.title, @user)

      column_value = @item.memex_project_column_values.find { |val| val.memex_project_column_id == title_column.id }

      assert column_value.present?
      assert column_value.persisted?
    end

    test "builds and does not persist a value if the item is not persisted" do
      issue = create(:issue, title: "Fix this")
      item = build(:memex_project_item, content: issue)
      title_column = item.memex_project.find_column_by_name_or_id(MemexProjectColumn::TITLE_COLUMN_NAME)

      refute item.memex_project_column_values.find { |val| val.memex_project_column_id == title_column.id }

      assert item.send(:set_json_value, title_column, item.denormalized_title_value, issue.title, @user)

      column_value = item.memex_project_column_values.find { |val| val.memex_project_column_id == title_column.id }

      assert column_value.present?
      refute column_value.persisted?
    end
  end

  context "#content_url" do
    test "matches an issue URL for an issue item" do
      issue = create(:issue)
      memex_item = create(:memex_project_item, :with_denormalized_title, priority: nil, content: issue)
      title_column = memex_item.memex_project.columns.find(&:title?)
      prefill_result = MemexProjectItemPrefiller.new(
        [memex_item],
        columns: [title_column],
        read_denormalized_title: true,
        title_column: title_column
      ).prefill

      assert_equal memex_item.send(:content_url, prefilled_associations: prefill_result), issue.url
    end

    test "matches a pull request URL for a pull request item" do
      pull = create(:pull_request, :disable_disk_access, repository: @repo, user: @user)
      memex_item = create(:memex_project_item, :with_denormalized_title, priority: nil, content: pull)
      title_column = memex_item.memex_project.columns.find(&:title?)
      prefill_result = MemexProjectItemPrefiller.new(
        [memex_item],
        columns: [title_column],
        read_denormalized_title: true,
        title_column: title_column
      ).prefill

      assert_equal memex_item.send(:content_url, prefilled_associations: prefill_result), pull.url
    end

    test "returns nil for a draft issue item" do
      draft_issue = create(:draft_issue)
      memex_item = create(:memex_project_item, :with_denormalized_title, priority: nil, content: draft_issue)
      title_column = memex_item.memex_project.columns.find(&:title?)
      prefill_result = MemexProjectItemPrefiller.new(
        [memex_item],
        columns: [title_column],
        read_denormalized_title: true,
        title_column: title_column
      ).prefill

      assert_nil memex_item.send(:content_url, prefilled_associations: prefill_result)
    end

    test "returns nil when no data has been denormalized for the content object" do
      issue = create(:issue)
      memex_item = create(:memex_project_item, priority: nil, content: issue)
      title_column = memex_item.memex_project.columns.find(&:title?)
      prefill_result = MemexProjectItemPrefiller.new(
        [memex_item],
        columns: [title_column],
        read_denormalized_title: true,
        title_column: title_column
      ).prefill

      # Make sure there's no denormalized title data.
      assert_nil memex_item.memex_project_column_values.where(memex_project_column_id: title_column.id).first

      assert_nil memex_item.send(:content_url, prefilled_associations: prefill_result)
    end

    test "returns nil when the repository for the content object can't be derived from denormalized data" do
      issue = create(:issue)
      memex_item = create(:memex_project_item, priority: nil, content: issue)
      memex_item.update_column(:repository_id, nil)
      title_column = memex_item.memex_project.columns.find(&:title?)
      prefill_result = MemexProjectItemPrefiller.new(
        [memex_item],
        columns: [title_column],
        read_denormalized_title: true,
        title_column: title_column
      ).prefill

      # Make sure no repository can be derived from the denormalized data.
      assert_nil prefill_result.repository(memex_item)

      assert_nil memex_item.send(:content_url, prefilled_associations: prefill_result)
    end
  end

  test "destroys an associated draft issue" do
    draft = create(:draft_issue)
    item = draft.memex_project_item

    old_draft_id = draft.id
    old_item_id = item.id

    assert DraftIssue.exists?(old_draft_id)
    assert MemexProjectItem.exists?(old_item_id)

    item.destroy!

    refute DraftIssue.exists?(old_draft_id)
    refute MemexProjectItem.exists?(old_item_id)
  end

  test "does not destroy associated content that is not a draft issue" do
    issue = create(:issue)
    item = create(:memex_project_item, content: issue)

    issue_id = issue.id
    old_item_id = item.id

    assert Issue.exists?(issue_id)
    assert MemexProjectItem.exists?(old_item_id)

    item.destroy!

    assert Issue.exists?(issue_id)
    refute MemexProjectItem.exists?(old_item_id)
  end

  context "identity predicates" do
    MemexProjectItem::VALID_CONTENT_TYPES.map(&:underscore).each do |type|
      test "creates a predicate method for content type: #{type}" do
        item = build(:memex_project_item, content: build(type.to_sym))
        assert_predicate item, :"#{type}?"
      end
    end
  end

  context "#can_convert_to_issue?" do
    test "draft issues can be converted to issue" do
      content = create(:draft_issue)
      memex_item = build(:memex_project_item, content: content)

      assert memex_item.can_convert_to_issue?
    end

    test "issue cannot be converted to issue" do
      content = create(:issue)
      memex_item = build(:memex_project_item, content: content)

      refute memex_item.can_convert_to_issue?
    end

    test "pull request cannot be converted to issue" do
      content = create(:pull_request, :disable_disk_access)
      memex_item = build(:memex_project_item, content: content)

      refute memex_item.can_convert_to_issue?
    end
  end

  context "notify socket subscribers after commit" do
    test "draft issue create does nothing" do
      draft_issue = create(:draft_issue)
      @issue.class.any_instance.expects(:notify_socket_subscribers).never
      memex_project_item = create(:memex_project_item, memex_project: @memex, content: draft_issue)
    end

    test "draft issue update does nothing" do
      draft_issue = create(:draft_issue)
      memex_project_item = create(:memex_project_item, memex_project: @memex, content: draft_issue)

      @issue.class.any_instance.expects(:notify_socket_subscribers).never
      memex_project_item.archive!
    end

    test "draft issue destroy does nothing" do
      draft_issue = create(:draft_issue)
      memex_project_item = create(:memex_project_item, memex_project: @memex, content: draft_issue)

      @issue.class.any_instance.expects(:notify_socket_subscribers).never
      memex_project_item.destroy!
    end

    test "issue create" do
      @issue.class.any_instance.expects(:notify_socket_subscribers).once
      memex_project_item = create(:memex_project_item, memex_project: @memex, content: @issue)
    end

    test "issue update" do
      memex_project_item = create(:memex_project_item, memex_project: @memex, content: @issue)

      @issue.class.any_instance.expects(:notify_socket_subscribers).once
      memex_project_item.archive!
    end

    test "issue destroy" do
      memex_project_item = create(:memex_project_item, memex_project: @memex, content: @issue)

      @issue.class.any_instance.expects(:notify_socket_subscribers).once
      memex_project_item.destroy!
    end

    test "pull request create" do
      @pull.class.any_instance.expects(:notify_socket_subscribers).once
      memex_project_item = create(:memex_project_item, memex_project: @memex, content: @pull)
    end

    test "pull request update" do
      memex_project_item = create(:memex_project_item, memex_project: @memex, content: @pull)

      @pull.class.any_instance.expects(:notify_socket_subscribers).once
      memex_project_item.archive!
    end

    test "pull request destroy" do
      memex_project_item = create(:memex_project_item, memex_project: @memex, content: @pull)

      @pull.class.any_instance.expects(:notify_socket_subscribers).once
      memex_project_item.destroy!
    end
  end

  context "synchronize index after commit" do
    test "issue create" do
      @issue.class.any_instance.expects(:synchronize_search_index).once
      memex_project_item = create(:memex_project_item, memex_project: @memex, content: @issue)
    end

    test "issue destroy" do
      memex_project_item = create(:memex_project_item, memex_project: @memex, content: @issue)

      @issue.class.any_instance.expects(:synchronize_search_index).once
      memex_project_item.destroy!
    end

    test "pull request create" do
      @pull.class.any_instance.expects(:synchronize_search_index).once
      memex_project_item = create(:memex_project_item, memex_project: @memex, content: @pull)
    end

    test "pull request destroy" do
      memex_project_item = create(:memex_project_item, memex_project: @memex, content: @pull)

      @pull.class.any_instance.expects(:synchronize_search_index).once
      memex_project_item.destroy!
    end
  end

  context "instrumentation" do

    context "#project item metadata update" do
      test "publishes metadata event to hydro on archive" do
        Timecop.freeze do
          item = create(:memex_project_item)
          GitHub.context.push(actor_id: item.creator.id)
          reset_hydro
          item.archive!
          assert_hydro_published({
            actor: Hydro::EntitySerializer.user(item.creator),
            memex_project: Hydro::EntitySerializer.memex_project(item.memex_project),
            memex_project_item: Hydro::EntitySerializer.memex_project_item(item),
          },
            schema: "github.memex.v0.ProjectItemMetadataUpdate",
            ignore_extra_keys: true,
          )
        end
      end

      test "publishes metadata event to hydro on touch" do
        Timecop.freeze do
          item = create(:memex_project_item)
          GitHub.context.push(actor_id: item.creator.id)
          reset_hydro
          item.touch
          assert_hydro_published({
            actor: Hydro::EntitySerializer.user(item.creator),
            memex_project: Hydro::EntitySerializer.memex_project(item.memex_project),
            memex_project_item: Hydro::EntitySerializer.memex_project_item(item),
          },
            schema: "github.memex.v0.ProjectItemMetadataUpdate",
            ignore_extra_keys: true,
          )
        end
      end

      test "does not publish metadata event to hydro when an irrelevant attribute is changed" do
        GitHub.context.push(actor_id: @user.id)
        reset_hydro
        @item.content.close
        @item.validate!
        assert @item.will_save_change_to_attribute?(:issue_closed_at)
        @item.save!
        refute_hydro_messages(schema: "github.memex.v0.ProjectItemMetadataUpdate")
      end
    end

    test "publishes to hydro on item create" do
      owner = create(:verified_user)
      member = create(:verified_user)
      org = create(:organization, admin: owner)
      org.add_member(member)
      memex = create(:memex_project, owner: org)
      now = DateTime.new(2021, 05, 06)

      Timecop.freeze(now) do
        item = create(:memex_project_item, memex_project: memex, creator: owner)

        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(owner),
          memex_project: Hydro::EntitySerializer.memex_project(memex),
          memex_project_item: Hydro::EntitySerializer.memex_project_item(item),
          performed_at: now,
          name: MemexProjectItem::ON_CREATE_INSTRUMENTATION_KEY
        }, schema: "github.memex.v1.Event")

        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(owner),
          memex_project: Hydro::EntitySerializer.memex_project(memex),
          memex_project_item: Hydro::EntitySerializer.memex_project_item(item),
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        }, schema: "github.memex.v0.ProjectItemCreate")

        GitHub.context.push(actor_id: member.id)
        item.archive!

        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(member),
          memex_project: Hydro::EntitySerializer.memex_project(memex),
          memex_project_item: Hydro::EntitySerializer.memex_project_item(item),
          performed_at: now,
          name: MemexProjectItem::ON_UPDATE_INSTRUMENTATION_KEY
        }, schema: "github.memex.v1.Event")

        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(member),
          memex_project: Hydro::EntitySerializer.memex_project(memex),
          memex_project_item: Hydro::EntitySerializer.memex_project_item(item),
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          previous_values: item.previous_changes&.to_s,
          creator: Hydro::EntitySerializer.user(owner)
        }, schema: "github.memex.v0.ProjectItemUpdate")

        item.destroy!

        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(member),
          memex_project: Hydro::EntitySerializer.memex_project(memex),
          memex_project_item: Hydro::EntitySerializer.memex_project_item(item),
          performed_at: now,
          name: MemexProjectItem::ON_DESTROY_INSTRUMENTATION_KEY
        }, schema: "github.memex.v1.Event")

        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(member),
          memex_project: Hydro::EntitySerializer.memex_project(memex),
          memex_project_item: Hydro::EntitySerializer.memex_project_item(item),
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash)
        }, schema: "github.memex.v0.ProjectItemDestroy")
      end
    end
  end

  context "completions" do
    test "returns empty hash when the graph client returns an error" do
      issue_graph_client = mock("issue_graph_client")
      GitHub.stubs(:issues_graph_api_client_strict).returns(issue_graph_client)
      GitHub.flipper[:tasklist_block].enable
      GitHub.flipper[:optimize_single_memex_hierarchy_prefill].disable
      GitHub.flipper[:project_hierarchy_columns].enable
      GitHub.flipper[:issues_graph_api_disable_denormalized_read].disable

      issue_graph_client.expects(:get_project_item_completions)
      .returns(error_result("some error"))
      .at_least(1)

      @memex.memex_project_items.each do |item|
        assert_equal({}, item.completion)
      end
    end

    test "returns completion" do
      GitHub.flipper[:tasklist_block].enable
      GitHub.flipper[:project_hierarchy_columns].enable
      GitHub.flipper[:issues_graph_api_disable_denormalized_read].disable
      issue_graph_client = mock("issue_graph_client")
      GitHub.stubs(:issues_graph_api_client_strict).returns(issue_graph_client)

      issue = @item.content

      issue_graph_client.expects(:get_project_item_completions)
      .returns(as_completions_result([
        { key: { ownerId: issue.repository.owner_id, itemId: issue.id }, completed: 4, total: 10, percent: 40 }
      ]))
      .at_least(1)

      assert_equal 4, @item.completion.dig(:completed)
      assert_equal 10, @item.completion.dig(:total)
      assert_equal 40, @item.completion.dig(:percent)
    end

    test "does not query for completions if memex_table_without_limits is enabled" do
      GitHub.flipper[:tasklist_block].enable
      GitHub.flipper[:project_hierarchy_columns].enable
      GitHub.flipper[:issues_graph_api_disable_denormalized_read].disable
      issue_graph_client = mock("issue_graph_client")
      GitHub.stubs(:issues_graph_api_client_strict).returns(issue_graph_client)

      # Memex without limits feature flags can be set globally or on the Memex project
      GitHub.flipper[:memex_mwl_allow_tasklist_columns].disable
      GitHub.flipper[:memex_table_without_limits].enable(@memex)

      issue = @item.content

      issue_graph_client.expects(:get_project_item_completions)
      .returns(as_completions_result([
        { key: { ownerId: issue.repository.owner_id, itemId: issue.id }, completed: 4, total: 10, percent: 40 }
      ]))
      .never

      assert_equal({}, @item.completion)
    end

    test "does not query for completions if memex_table_without_limits is enabled unless memex_mwl_allow_tasklist_columns is also enabled" do
      GitHub.flipper[:tasklist_block].enable
      GitHub.flipper[:project_hierarchy_columns].enable
      GitHub.flipper[:issues_graph_api_disable_denormalized_read].disable
      issue_graph_client = mock("issue_graph_client")
      GitHub.stubs(:issues_graph_api_client_strict).returns(issue_graph_client)

      # Memex without limits feature flags can be set globally or on the Memex project
      GitHub.flipper[:memex_mwl_allow_tasklist_columns].disable
      GitHub.flipper[:memex_table_without_limits].enable(@memex)
      GitHub.flipper[:memex_mwl_allow_tasklist_columns].enable(@memex)

      issue = @item.content

      issue_graph_client.expects(:get_project_item_completions)
      .returns(as_completions_result([
        { key: { ownerId: issue.repository.owner_id, itemId: issue.id }, completed: 4, total: 10, percent: 40 }
      ]))
      .at_least(1)

      assert_equal 4, @item.completion.dig(:completed)
      assert_equal 10, @item.completion.dig(:total)
      assert_equal 40, @item.completion.dig(:percent)
    end

    test "returns completion using hierarchy_state when enabled" do
      GitHub.flipper[:tasklist_block].enable
      GitHub.flipper[:optimize_single_memex_hierarchy_prefill].enable
      GitHub.flipper[:issue_hierarchy_state].enable
      GitHub.flipper[:issues_graph_api_concurrent_faraday].disable
      GitHub.flipper[:project_hierarchy_columns].enable
      GitHub.flipper[:issues_graph_api_disable_denormalized_read].disable

      issue_graph_client = mock("issue_graph_client")
      GitHub.stubs(:issues_graph_api_client_strict).returns(issue_graph_client)

      tracking_parent = IssuesGraph::Proto::Issue.new(
        completion: IssuesGraph::Proto::Completion.new(
          completed: 4,
          total: 10,
          percent: 40
        )
      )
      issue_graph_client.expects(:get_issue)
        .returns(as_tracked_issue_result(parent: tracking_parent))
        .once

      assert_equal 4, @item.completion.dig(:completed)
      assert_equal 10, @item.completion.dig(:total)
      assert_equal 40, @item.completion.dig(:percent)
    end
  end

  context "async_spammy_by_viewer", spammy_only: true do
    context "draft issue" do
      test "returns false if draft was not authored by spammy user" do
        other_user = create(:verified_user)
        memex = create(:memex_project, owner: @user)
        memex.update_organization_wide_role("project_admin", other_user)

        draft_item = build(:memex_project_item, memex_project: memex, creator: other_user)
        draft_item.content = @draft_item.build_draft_issue(title: Faker::Lorem.unique.word)
        draft_item.save!

        refute draft_item.async_spammy_by_viewer?(@user).sync
      end

      test "returns true if draft was authored by spammy user" do
        other_user = create(:verified_user)
        memex = create(:memex_project, owner: @user)
        memex.update_organization_wide_role("project_admin", other_user)

        draft_item = build(:memex_project_item, memex_project: memex, creator: other_user)
        draft_item.content = @draft_item.build_draft_issue(title: Faker::Lorem.unique.word)
        draft_item.save!

        perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
          other_user.mark_as_spammy
        end
        draft_item.reload

        assert draft_item.async_spammy_by_viewer?(@user).sync
      end
    end

    context "issue" do
      test "returns false if issue was not authored by spammy user" do
        other_user = create(:verified_user)
        memex = create(:memex_project, owner: @user)
        memex.update_organization_wide_role("project_admin", other_user)

        issue = create(:issue, user: other_user)
        memex_item = create(:memex_project_item, memex_project: memex, content: issue, creator: other_user)

        refute memex_item.async_spammy_by_viewer?(@user).sync
      end

      test "returns true if issue item was authored by spammy user" do
        other_user = create(:verified_user)
        memex = create(:memex_project, owner: @user)
        memex.update_organization_wide_role("project_admin", other_user)

        issue = create(:issue, user: @user)
        memex_item = create(:memex_project_item, memex_project: memex, content: issue, creator: other_user)

        perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
          other_user.mark_as_spammy
        end
        memex_item.reload

        assert memex_item.async_spammy_by_viewer?(@user).sync
      end

      test "returns true if issue was authored by spammy user" do
        other_user = create(:verified_user)
        memex = create(:memex_project, owner: @user)
        memex.update_organization_wide_role("project_admin", other_user)

        issue = create(:issue, user: other_user)
        memex_item = create(:memex_project_item, memex_project: memex, content: issue, creator: @user)

        perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
          other_user.mark_as_spammy
        end
        memex_item.reload

        assert memex_item.async_spammy_by_viewer?(@user).sync
      end
    end

    context "pull request" do
      test "returns false if pull request was not authored by spammy user" do
        other_user = create(:verified_user)
        memex = create(:memex_project, owner: @user)
        memex.update_organization_wide_role("project_admin", other_user)

        pull = create(:pull_request, :disable_disk_access, repository: @repo, user: other_user)
        memex_item = create(:memex_project_item, memex_project: memex, content: pull, creator: other_user)

        refute memex_item.async_spammy_by_viewer?(@user).sync
      end

      test "returns true if pull request item was authored by spammy user" do
        other_user = create(:verified_user)
        memex = create(:memex_project, owner: @user)
        memex.update_organization_wide_role("project_admin", other_user)

        pull = create(:pull_request, :disable_disk_access, repository: @repo, user: @user)
        memex_item = create(:memex_project_item, memex_project: memex, content: pull, creator: other_user)

        perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
          other_user.mark_as_spammy
        end
        memex_item.reload

        assert memex_item.async_spammy_by_viewer?(@user).sync
      end

      test "returns true if pull request was authored by spammy user" do
        other_user = create(:verified_user)
        memex = create(:memex_project, owner: @user)
        memex.update_organization_wide_role("project_admin", other_user)

        pull = create(:pull_request, :disable_disk_access, repository: @repo, user: other_user)
        memex_item = create(:memex_project_item, memex_project: memex, content: pull, creator: @user)

        perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
          other_user.mark_as_spammy
        end
        memex_item.reload

        assert memex_item.async_spammy_by_viewer?(@user).sync
      end
    end
  end

  test "increments memex_project_visits for creator/memex/owner on creation" do
    owner = create(:verified_user)
    member = create(:verified_user)
    org = create(:organization, admin: owner)
    org.add_member(member)
    memex = create(:memex_project, owner: org)
    now = DateTime.new(2021, 05, 06)

    Timecop.freeze(now) do
      refute memex.memex_project_visits.find_by(viewer: member)

      item = create(:memex_project_item, memex_project: memex, creator: member)
      visit = memex.memex_project_visits.find_by(viewer: member)

      assert visit
      assert_equal visit.last_visited_at, now
    end
  end

  context "tracked by items" do
    test "raises MemexProjectItem::ItemPrefillError when the graph client returns an error" do
      issue_graph_client = mock("issue_graph_client")
      GitHub.stubs(:issues_graph_api_client_strict).returns(issue_graph_client)
      GitHub.flipper[:tasklist_block].enable
      GitHub.flipper[:project_hierarchy_columns].enable
      GitHub.flipper[:issues_graph_api_disable_denormalized_read].disable

      issue_graph_client.expects(:get_project_tracked_by_items)
        .with(has_entries(owner_id: @memex.owner_id, item_id: @memex.id))
        .returns(error_result("graph error"))

      assert_raises(MemexProjectItem::ItemPrefillError) do
        GitHub::PrefillAssociations
          .prefill_batch_method(@memex.memex_project_items, :tracked_by_items)
      end
    end

    test "raises MemexProjectItem::ItemPrefillError when the graph client raises a Faraday::Error" do
      issue_graph_client = mock("issue_graph_client")
      GitHub.stubs(:issues_graph_api_client_strict).returns(issue_graph_client)
      GitHub.flipper[:tasklist_block].enable
      GitHub.flipper[:project_hierarchy_columns].enable
      GitHub.flipper[:issues_graph_api_disable_denormalized_read].disable

      result = ::IssuesGraph::Result.error(::Twirp::Error.unknown("error"))

      issue_graph_client.expects(:get_project_tracked_by_items)
        .with(has_entries(owner_id: @memex.owner_id, item_id: @memex.id))
        .returns(result)

      assert_raises(MemexProjectItem::ItemPrefillError) do
        GitHub::PrefillAssociations
          .prefill_batch_method(@memex.memex_project_items, :tracked_by_items)
      end
    end

    test "returns tracked by items" do
      issue_graph_client = mock("issue_graph_client")
      GitHub.flipper[:tasklist_block].enable
      GitHub.flipper[:optimize_single_memex_hierarchy_prefill].disable
      GitHub.flipper[:project_hierarchy_columns].enable
      GitHub.flipper[:issues_graph_api_disable_denormalized_read].disable
      GitHub.stubs(:issues_graph_api_client_strict).returns(issue_graph_client)

      uuid = "74ba4f92-a35e-4e2b-9418-f607a1b1bdc8"
      parent_issue = create(:issue, repository: @repo, user: @user)
      child_issue  = @item.content
      repo = parent_issue.repository

      expected = {
        key: { ownerId: repo.owner_id, itemId: parent_issue.id, primaryKey: { uuid: uuid } },
        title: parent_issue.title,
        url: parent_issue.url,
        state: parent_issue.state.to_s,
        repoName: repo.name,
        repoId: repo.id,
        userName: @user.name,
        number: parent_issue.number,
        labels: [],
        assignees: [],
        stateReason: parent_issue.state_reason.to_s,
        completion: {
          key: { ownerId: repo.owner_id, itemId: parent_issue.id, primaryKey: { uuid: uuid } },
          completed: 4, total: 10, percent: 40
        },
        position: 0,
        itemType: :ISSUE,
      }

      issue_graph_client.expects(:get_project_tracked_by_items)
        .with(has_entries(owner_id: @memex.owner_id, item_id: @memex.id))
        .returns(as_tracked_by_items_result([
          {
            key: { ownerId: repo.owner_id, itemId: child_issue.id },
            trackedByItems: [expected, expected]
          }
        ]))

      expected_key = build_proto_key(owner_id: repo.owner_id, item_id: parent_issue.id, uuid: uuid)
      expected_issue = expected.deep_transform_keys { |key| key.to_s.underscore }.deep_symbolize_keys!
      assert_equal [
        TasklistBlocks::Issue.from_proto(issue: build_proto_issue(
            **expected_issue.merge({
              key: expected_key,
              completion: build_proto_completion(key: expected_key, completed: 4, total: 10, percent: 40)
            })
          )
        ).to_h
      ], @item.tracked_by_items.to_a.map(&:to_h)
    end

    test "does not query for tracked by items if memex_table_without_limits is enabled" do
      issue_graph_client = mock("issue_graph_client")
      GitHub.flipper[:tasklist_block].enable
      GitHub.flipper[:optimize_single_memex_hierarchy_prefill].disable
      GitHub.flipper[:project_hierarchy_columns].enable
      GitHub.flipper[:issues_graph_api_disable_denormalized_read].disable
      GitHub.stubs(:issues_graph_api_client_strict).returns(issue_graph_client)

      # Memex without limits feature flags can be set globally or on the Memex project
      GitHub.flipper[:memex_mwl_allow_tasklist_columns].disable
      GitHub.flipper[:memex_table_without_limits].enable(@memex)

      uuid = "74ba4f92-a35e-4e2b-9418-f607a1b1bdc8"
      parent_issue = create(:issue, repository: @repo, user: @user)
      child_issue  = @item.content
      repo = parent_issue.repository

      expected = {
        key: { ownerId: repo.owner_id, itemId: parent_issue.id, primaryKey: { uuid: uuid } },
        title: parent_issue.title,
        url: parent_issue.url,
        state: parent_issue.state.to_s,
        repoName: repo.name,
        repoId: repo.id,
        userName: @user.name,
        number: parent_issue.number,
        labels: [],
        assignees: [],
        stateReason: parent_issue.state_reason.to_s,
        completion: {
          key: { ownerId: repo.owner_id, itemId: parent_issue.id, primaryKey: { uuid: uuid } },
          completed: 4, total: 10, percent: 40
        },
        position: 0,
        itemType: :ISSUE,
      }

      issue_graph_client.expects(:get_project_tracked_by_items)
        .with(has_entries(owner_id: @memex.owner_id, item_id: @memex.id))
        .returns(as_tracked_by_items_result([
          {
            key: { ownerId: repo.owner_id, itemId: child_issue.id },
            trackedByItems: [expected, expected]
          }
        ]))
        .never

      assert_equal [], @item.tracked_by_items.to_a.map(&:to_h)
    end

    test "does not query for tracked by items if memex_table_without_limits is enabled unless memex_mwl_allow_tasklist_columns is also enabled" do
      issue_graph_client = mock("issue_graph_client")
      GitHub.flipper[:tasklist_block].enable
      GitHub.flipper[:optimize_single_memex_hierarchy_prefill].disable
      GitHub.flipper[:project_hierarchy_columns].enable
      GitHub.flipper[:issues_graph_api_disable_denormalized_read].disable
      GitHub.stubs(:issues_graph_api_client_strict).returns(issue_graph_client)

      # Memex without limits feature flags can be set globally or on the Memex project
      GitHub.flipper[:memex_mwl_allow_tasklist_columns].disable
      GitHub.flipper[:memex_table_without_limits].enable(@memex)
      GitHub.flipper[:memex_mwl_allow_tasklist_columns].enable(@memex)

      uuid = "74ba4f92-a35e-4e2b-9418-f607a1b1bdc8"
      parent_issue = create(:issue, repository: @repo, user: @user)
      child_issue  = @item.content
      repo = parent_issue.repository

      expected = {
        key: { ownerId: repo.owner_id, itemId: parent_issue.id, primaryKey: { uuid: uuid } },
        title: parent_issue.title,
        url: parent_issue.url,
        state: parent_issue.state.to_s,
        repoName: repo.name,
        repoId: repo.id,
        userName: @user.name,
        number: parent_issue.number,
        labels: [],
        assignees: [],
        stateReason: parent_issue.state_reason.to_s,
        completion: {
          key: { ownerId: repo.owner_id, itemId: parent_issue.id, primaryKey: { uuid: uuid } },
          completed: 4, total: 10, percent: 40
        },
        position: 0,
        itemType: :ISSUE,
      }

      issue_graph_client.expects(:get_project_tracked_by_items)
        .with(has_entries(owner_id: @memex.owner_id, item_id: @memex.id))
        .returns(as_tracked_by_items_result([
          {
            key: { ownerId: repo.owner_id, itemId: child_issue.id },
            trackedByItems: [expected, expected]
          }
        ]))
        .at_least(1)

      expected_key = build_proto_key(owner_id: repo.owner_id, item_id: parent_issue.id, uuid: uuid)
      expected_issue = expected.deep_transform_keys { |key| key.to_s.underscore }.deep_symbolize_keys!
      assert_equal [
        TasklistBlocks::Issue.from_proto(issue: build_proto_issue(
            **expected_issue.merge({
              key: expected_key,
              completion: build_proto_completion(key: expected_key, completed: 4, total: 10, percent: 40)
            })
          )
        ).to_h
      ], @item.tracked_by_items.to_a.map(&:to_h)
    end

    test "returns tracked by items via hierarchy_state for a single item" do
      GitHub.flipper[:tasklist_block].enable
      GitHub.flipper[:optimize_single_memex_hierarchy_prefill].enable
      GitHub.flipper[:issue_hierarchy_state].enable
      GitHub.flipper[:issues_graph_api_concurrent_faraday].disable
      GitHub.flipper[:project_hierarchy_columns].enable
      GitHub.flipper[:issues_graph_api_disable_denormalized_read].disable

      uuid = "74ba4f92-a35e-4e2b-9418-f607a1b1bdc8"
      parent_issue = create(:issue, repository: @repo, user: @user)
      repo = parent_issue.repository

      expected = {
        key: { ownerId: repo.owner_id, itemId: parent_issue.id, primaryKey: { uuid: uuid } },
        title: parent_issue.title,
        url: parent_issue.url,
        state: parent_issue.state.to_s,
        repoName: repo.name,
        repoId: repo.id,
        userName: @user.name,
        number: parent_issue.number,
        labels: [],
        assignees: [],
        stateReason: parent_issue.state_reason.to_s,
        completion: {
          key: { ownerId: repo.owner_id, itemId: parent_issue.id, primaryKey: { uuid: uuid } },
          completed: 4, total: 10, percent: 40
        },
        position: 0,
        itemType: :ISSUE
      }

      issue_graph_client = mock("issue_graph_client")
      issue_graph_client.expects(:get_issue)
        .returns(as_tracked_issue_result(tracking_issues: [], tracked_by_issues: [expected]))
        .once
      GitHub.stubs(:issues_graph_api_client_strict).returns(issue_graph_client)

      expected_key = build_proto_key(owner_id: repo.owner_id, item_id: parent_issue.id, uuid: uuid)
      expected_issue = expected.deep_transform_keys { |key| key.to_s.underscore }.deep_symbolize_keys!
      assert_equal [
          TasklistBlocks::Issue.from_proto(issue: build_proto_issue(
            **expected_issue.merge({
              key: expected_key,
              completion: build_proto_completion(key: expected_key, completed: 4, total: 10, percent: 40)
            })
          )
        )
      ], @item.tracked_by_items
    end

    test "returns tracked by items via hierarchy_state for a single item excluding empty objects" do
      GitHub.flipper[:tasklist_block].enable
      GitHub.flipper[:optimize_single_memex_hierarchy_prefill].enable
      GitHub.flipper[:issue_hierarchy_state].enable
      GitHub.flipper[:issues_graph_api_concurrent_faraday].disable
      GitHub.flipper[:project_hierarchy_columns].enable
      GitHub.flipper[:issues_graph_api_disable_denormalized_read].disable

      uuid = "74ba4f92-a35e-4e2b-9418-f607a1b1bdc8"
      parent_issue = create(:issue, repository: @repo, user: @user)
      repo = parent_issue.repository

      expected = {
        key: { ownerId: repo.owner_id, itemId: parent_issue.id, primaryKey: { uuid: uuid } },
        title: parent_issue.title,
        url: parent_issue.url,
        state: parent_issue.state.to_s,
        repoName: repo.name,
        repoId: repo.id,
        userName: @user.name,
        number: parent_issue.number,
        labels: [],
        assignees: [],
        stateReason: parent_issue.state_reason.to_s,
        completion: {
          key: { ownerId: repo.owner_id, itemId: parent_issue.id, primaryKey: { uuid: uuid } },
          completed: 4, total: 10, percent: 40
        },
        position: 0,
        itemType: :ISSUE,
      }

      issue_graph_client = mock("issue_graph_client")
      issue_graph_client.expects(:get_issue)
        .returns(
          IssuesGraph::Result.success(
            IssuesGraph::Proto::GetIssueResponse.new(
              issue: nil,
              tracking: [],
              trackedBy: [
                IssuesGraph::Proto::TrackingBlock.new(
                  issues: []
                ),
                IssuesGraph::Proto::TrackingBlock.new(
                  issues: [expected]
                ),
                IssuesGraph::Proto::TrackingBlock.new(
                  issues: []
                )
              ]
            )
          )
        )
        .once
      GitHub.stubs(:issues_graph_api_client_strict).returns(issue_graph_client)

      expected_key = build_proto_key(owner_id: repo.owner_id, item_id: parent_issue.id, uuid: uuid)
      expected_issue = expected.deep_transform_keys { |key| key.to_s.underscore }.deep_symbolize_keys!
      assert_equal [
        TasklistBlocks::Issue.from_proto(issue: build_proto_issue(
            **expected_issue.merge({
              key: expected_key,
              completion: build_proto_completion(key: expected_key, completed: 4, total: 10, percent: 40)
            })
          )
        )
      ], @item.tracked_by_items
    end
  end

  context "children for parent" do
    test "returns an empty array when issue id is falsy" do
      assert_equal [], MemexProjectItem.children_for_parent(nil)
    end

    test "returns an empty array when the graph client returns an error" do
      issue_graph_client = mock("issue_graph_client")
      GitHub.stubs(:issues_graph_api_client_strict).returns(issue_graph_client)

      parent_issue = create(:issue, repository: @repo, user: @user)

      issue_graph_client.expects(:get_issue)
      .with(
        has_entries(
          key: {
            ownerId: @repo.owner_id,
            itemId: parent_issue.id
          }
        )
      ).raises(Faraday::Error.new("boom!"))

      assert_equal [], MemexProjectItem.children_for_parent(parent_issue)
    end

    test "returns an empty array when the graph client GetIssue API returns an error as result" do
      issue_graph_client = mock("issue_graph_client")
      GitHub.stubs(:issues_graph_api_client_strict).returns(issue_graph_client)

      parent_issue = create(:issue, repository: @repo, user: @user)

      issue_graph_client.expects(:get_issue)
      .with(
        has_entries(
          key: {
            ownerId: @repo.owner_id,
            itemId: parent_issue.id
          }
        )
      ).returns(error_result("graph error"))

      assert_equal [], MemexProjectItem.children_for_parent(parent_issue)
    end

    test "returns child issues for a given parent issue" do
      issue_graph_client = mock("issue_graph_client")
      GitHub.stubs(:issues_graph_api_client_strict).returns(issue_graph_client)

      uuid = SecureRandom.uuid
      parent_issue = create(:issue, repository: @repo, user: @user)

      tracking_parent = create_tracking_parent(uuid, parent_issue)
      tracking_issue = IssuesGraph::Proto::Issue.new(
        key: IssuesGraph::Proto::Key.new(itemId: 2, ownerId: @repo.id),
        repoId: @repo.id,
        userName: @user.login,
        repoName: @repo.name,
        number: 2,
        title: "tracked issue 2",
        url: "http://dummy-url.github.com/#{@user.login}/#{@repo.name}/issues/2",
        state: "closed",

      )

      issue_graph_client.expects(:get_issue)
        .with(
          has_entries(
            key: {
              ownerId: @repo.owner_id,
              itemId: parent_issue.id
            }
          )
        ).returns(
          as_tracked_issue_result(
            uuid: uuid, parent: tracking_parent,
            tracking_issues: [tracking_issue]
          )
        )

      children, parent_completion = MemexProjectItem.children_for_parent(parent_issue)

      refute_empty children
      assert_equal [
        {
          uuid: nil, item_id: 2,
          title: tracking_issue["title"],
          state: tracking_issue["state"], state_reason: "",
          url: tracking_issue["url"],
          display_number: tracking_issue["number"],
          repository_id: @repo.id,
          repository_name: @repo.name,
          owner_login: @user.login,
          assignees: [], labels: [], position: 0,
          title_html: nil,
          completion: nil,
          item_type: :UNDEFINED,
          tracked_by_title: nil,
        },
      ], children.map { |issue| issue.to_h }

      assert_equal ({
        owner_id: @repo.owner_id, item_id: parent_issue.id, repository_id: @repo.id,
        completed: 1, total: 1, percent: 100
      }), parent_completion
    end

    test "rejects draft issues from children for a given parent issue" do
      issue_graph_client = mock("issue_graph_client")
      GitHub.stubs(:issues_graph_api_client_strict).returns(issue_graph_client)

      uuid = SecureRandom.uuid
      parent_issue = create(:issue, repository: @repo, user: @user)

      tracking_parent = create_tracking_parent(uuid, parent_issue)
      tracking_issues = [
        { item_id: 1, state: "closed" },
        { item_id: 2, state: "open" },
        { item_id: 3, state: "draft" },
        { item_id: 4, state: "draftClosed" },
      ].map do |i|
        IssuesGraph::Proto::Issue.new(
          key: IssuesGraph::Proto::Key.new(itemId: i[:item_id], ownerId: @repo.owner_id),
          repoId: @repo.id,
          userName: @user.login,
          repoName: @repo.name,
          number: 2,
          title: "tracked issue 2",
          url: "http://dummy-url.github.com/#{@user.login}/#{@repo.name}/issues/2",
          state: i[:state],
        )
      end

      issue_graph_client.expects(:get_issue)
        .with(
          has_entries(
            key: {
              ownerId: @repo.owner_id,
              itemId: parent_issue.id,
            }
          )
        ).returns(
          as_tracked_issue_result(
            uuid: uuid, parent: tracking_parent,
            tracking_issues: tracking_issues
          )
        )

      children, _ = MemexProjectItem.children_for_parent(parent_issue)

      assert_equal 2, children.length
      assert_equal %w[closed open], children.map { |i| i.state }
    end
  end

  private def create_tracking_parent(uuid, parent_issue)
    tracking_parent_key = IssuesGraph::Proto::Key.new(
      ownerId: @repo.owner_id,
      itemId: parent_issue.id,
      primaryKey: ::IssuesGraph::Proto::PrimaryKey.new(
        uuid: uuid,
      )
    )

    tracking_parent = IssuesGraph::Proto::Issue.new(
      key: tracking_parent_key,
      userName: @user.login,
      repoId: @repo.id,
      repoName: @repo.name,
      number: 1,
      title: "tracked issue",
      url: "http://dummy-url.github.com/#{@user.login}/#{@repo.name}/issues/1",
      state: "open",
      completion: IssuesGraph::Proto::Completion.new(
        key: tracking_parent_key,
        completed: 1,
        total: 1,
        percent: 100
      )
    )
  end
end
