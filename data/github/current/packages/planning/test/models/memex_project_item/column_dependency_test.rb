# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectItem::ColumnDependencyTest < GitHub::TestCase
  include HydroTestHelpers
  include MemexHelpers
  include SubIssuesHelpers

  ErrorMock = Struct.new(:error, :data, :error?)
  DataMock = Struct.new(:blocks)

  fixtures do
    @memex = create(:memex_project)
    @item = create(:memex_project_item, memex_project: @memex)
    @single_select_column = create(:single_select_memex_column, memex_project: @memex)
    @user = create(:user)
    @repo = create(:public_repository, owner: @user)
    @issue = create(:issue, user: @user, repository: @repo)
    @org_admin = create(:verified_user)
    @org = create(:organization, admin: @org_admin)
    @text_column = create(:memex_project_column, user_defined: true, data_type: :text, memex_project: @memex)
    @iteration_column = create(:iteration_memex_column, memex_project: @memex)
    @date_column = create(:memex_project_column, user_defined: true, data_type: :date, memex_project: @memex)
    @number_column = create(:memex_project_column, user_defined: true, data_type: :number, memex_project: @memex)
    @draft_item = build(:memex_project_item, memex_project: @memex, priority: 1)
    @draft_item.content = @draft_item.build_draft_issue(title: Faker::Lorem.unique.word)
    @draft_item.save!
  end

  setup do
    @iteration_options = @iteration_column.settings.dig("configuration", "iterations")
    @single_select_options = @single_select_column.settings["options"]
  end

  context "#column_value" do
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
      assert_nil item.column_value(column, require_prefilled_associations: false)

      # Returns login if single user
      assert item.set_column_value(column, [user_1.id], user_1)
      assert_equal "foo", item.reload.column_value(column, require_prefilled_associations: false)

      # Returns logins sorted and separated by commas if multiple users
      assert item.set_column_value(column, [user_1.id, user_2.id], user_1)
      assert_equal "bar, foo", item.reload.column_value(column, require_prefilled_associations: false)
    end

    test "returns single select" do
      # Returns nil if item has no single select option
      assert_nil @item.column_value(@single_select_column, require_prefilled_associations: false)

      # Returns the option name if item has a single select option
      single_select_option = @single_select_options.first
      assert @item.set_column_value(@single_select_column, single_select_option["id"], @user)

      value = @item.reload.column_value(@single_select_column, require_prefilled_associations: false)
      assert_equal single_select_option["name"], value
    end

    test "returns iteration" do
      # Returns nil if item has no iteration
      assert @item.set_column_value(@iteration_column, nil, @user)
      assert_nil @item.reload.column_value(@iteration_column, require_prefilled_associations: false)

      # Returns iteration title if item has an iteration
      assert @item.set_column_value(@iteration_column, @iteration_options[0]["id"], @user)
      assert_equal @iteration_options.first["title"], @item.reload.column_value(@iteration_column, require_prefilled_associations: false)
    end

    test "returns date in the correct format" do
      # Returns nil if item has no date
      assert_nil @item.column_value(@date_column, require_prefilled_associations: false)

      # Test date format with one digit month/day
      assert @item.set_column_value(@date_column, "2021-01-01", @user)
      assert_equal "Jan 1, 2021", @item.reload.column_value(@date_column, require_prefilled_associations: false)

      # Test date format with two digit month/day
      assert @item.set_column_value(@date_column, "2021-12-31", @user)
      assert_equal "Dec 31, 2021", @item.reload.column_value(@date_column, require_prefilled_associations: false)
    end

    test "returns repository" do
      repository_column = @memex.find_column_by_name_or_id(MemexProjectColumn::REPOSITORY_COLUMN_NAME)

      # draft issue has no repository
      draft_issue = create(:draft_issue, title: "github")
      item = create(:memex_project_item, content: draft_issue, memex_project: @memex)
      assert_nil item.reload.column_value(repository_column, require_prefilled_associations: false)

      # issue has a repository
      assert_equal @item.content.repository.name_with_owner, @item.column_value(repository_column, require_prefilled_associations: false)
    end

    test "returns parent issue" do
      parent_issue_column = @memex.find_column_by_name_or_id(MemexProjectColumn::PARENT_ISSUE_COLUMN_NAME)

      enable_feature_flag(:sub_issues)
      repository = create(:public_repository, owner: @user)
      repository = create(:repository, owner: @user)
      parent = create(:issue, repository:, user: @user)
      child1 = create(:issue, repository:, user: @user)
      parent.add_sub_issue!(child1, @user.id)
      item = create(:memex_project_item, memex_project: @memex, content: child1)

      assert_equal parent.title, item.reload.column_value(parent_issue_column, require_prefilled_associations: false)
    end

    test "returns sub issues progress" do
      enable_feature_flag(:sub_issues)

      sub_issues_progress_column = @memex.find_column_by_name_or_id(MemexProjectColumn::SUB_ISSUES_PROGRESS_COLUMN_NAME)

      issues = create_hierarchy! <<~HIERARCHY
      - parent
        - child1
        - child2
        - child3
      HIERARCHY

      parent = issues["parent"]
      child1 = issues["child1"]
      child2 = issues["child2"]

      child1&.close!
      child2&.close!

      parent&.recalculate_sub_issue_list!

      item = create(:memex_project_item, memex_project: @memex, content: parent)

      assert_equal "66", item.reload.column_value(sub_issues_progress_column, require_prefilled_associations: false)
    end

    test "returns text" do
      assert_nil @item.column_value(@text_column, require_prefilled_associations: false)

      assert @item.set_column_value(@text_column, "foo", @user)
      assert_equal "foo", @item.reload.column_value(@text_column, require_prefilled_associations: false)
    end

    test "returns whole numbers as a string without trailing zeros or decimal point" do
      column = create(:memex_project_column, memex_project: @memex, data_type: "number")

      assert_nil @item.column_value(column, require_prefilled_associations: false)
      assert @item.set_column_value(column, 42, @user)
      assert_equal "42", @item.reload.column_value(column, require_prefilled_associations: false)
    end

    test "returns non-whole numbers as a string with a decimal point" do
      column = create(:memex_project_column, memex_project: @memex, data_type: "number")

      assert_nil @item.column_value(column, require_prefilled_associations: false)
      assert @item.set_column_value(column, 42.9000, @user)
      assert_equal "42.9", @item.reload.column_value(column, require_prefilled_associations: false)
    end

    test "returns milestone" do
      item = create(:memex_project_item, content: @issue, memex_project: @memex)
      milestone = create(:milestone, repository: @issue.repository)
      milestone_column = @memex.find_column_by_name_or_id(MemexProjectColumn::MILESTONE_COLUMN_NAME)
      refute_nil milestone_column

      # Returns nil if milestone is not set
      assert_nil item.column_value(milestone_column, require_prefilled_associations: false)

      # Returns milestone title if milestone is set
      assert item.set_column_value(milestone_column, milestone.id, @user)
      assert_equal milestone.title, item.reload.column_value(milestone_column, require_prefilled_associations: false)
    end

    test "returns issue_type" do
      issue_type = create(:issue_type, owner: @org, name: "test")
      repository = create(:repository, owner: @org)
      enable_feature_flag(:issue_types, @org)
      issue = create(:issue, user: @org_admin, repository: repository, issue_type: nil)
      memex = create(:memex_project, owner: @org)
      item = create(:memex_project_item, content: issue, memex_project: memex)
      issue_type_column = memex.find_column_by_name_or_id(MemexProjectColumn::TYPE_COLUMN_NAME)

      # Returns nil if issue type is not set
      assert_nil item.column_value(issue_type_column, require_prefilled_associations: false)

      # Returns issue type name if issue type is set
      assert item.set_column_value(issue_type_column, issue_type.id, @org_admin)
      assert_equal issue_type.name, item.reload.column_value(issue_type_column, require_prefilled_associations: false)
    end

    context "labels" do
      test "returns a single label's name" do
        item = create(:memex_project_item, content: @issue, memex_project: @memex)
        label = create(:label, repository: @repo)
        label_column = @memex.find_column_by_name_or_id(MemexProjectColumn::LABELS_COLUMN_NAME)
        refute_nil label_column

        assert_empty item.column_value(label_column, require_prefilled_associations: false)
        assert item.set_column_value(label_column, [label.id], @user)
        assert_equal label.name, item.reload.column_value(label_column, require_prefilled_associations: false)
      end

      test "returns a list of label names" do
        item = create(:memex_project_item, content: @issue, memex_project: @memex)
        labels = create_list(:label, 3, repository: @repo)
        label_column = @memex.find_column_by_name_or_id(MemexProjectColumn::LABELS_COLUMN_NAME)

        assert_empty item.column_value(label_column, require_prefilled_associations: false)
        assert item.set_column_value(label_column, labels.map(&:id), @user)
        assert_same_elements labels.map(&:name),
          item.reload.column_value(label_column, require_prefilled_associations: false).split(", ")
      end
    end
  end

  context "#special_type_column_value" do
    # This block intentionally uses `send` to unit test the private
    # `MemexProjectItem#special_column_type_column_value` method. We have no
    # need outside of tests to make that method public, so while that's true
    # this technique allows to maintain a strong public interface while still
    # testing a reasonable complex sub-method. The public interface is also
    # tested separately at the integration test level.

    test "returns assignee column data for an issue" do
      # This adds the repository's owner as the assignee, which in this case is
      # @user.
      issue = create(:assigned_issue, repository: @repo)
      item = create(:memex_project_item, content: issue)

      assert_equal(
        [
          {
            avatarUrl: @user.primary_avatar_url(40),
            id: @user.id,
            login: @user.login,
            url: @user.permalink,
          },
        ],
        item.send(
          :special_type_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::ASSIGNEES_COLUMN_NAME),
          require_prefilled_associations: false
        )
      )
    end

    test "returns assignees column data for a pull request" do
      pull = create(
        :pull_request,
        :disable_disk_access,
        repository: @repo,
        user: @user
      ).tap do |p|
        p.issue.add_assignees([@user])
        p.issue.save!
      end
      item = create(:memex_project_item, content: pull)

      assert_equal(
        [
          {
            avatarUrl: @user.primary_avatar_url(40),
            id: @user.id,
            login: @user.login,
            url: @user.permalink,
          },
        ],
        item.send(
          :special_type_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::ASSIGNEES_COLUMN_NAME),
          require_prefilled_associations: false
        )
      )
    end

    test "returns alphabetized label column data for an issue" do
      # case insensitive alphabetical sort
      label1 = create(:label, repository: @repo, name: "Zebra")
      label2 = create(:label, repository: @repo, name: "camel")
      @repo.update!(labels: [label1, label2])

      issue = create(:issue, repository: @repo).tap do |i|
        i.add_labels([label1, label2])
        i.save!
      end
      item = create(:memex_project_item, content: issue)

      column_values = item.send(
        :special_type_column_value,
        MemexProjectColumn.default_column(MemexProjectColumn::LABELS_COLUMN_NAME),
        require_prefilled_associations: false
      )

      assert_equal issue.labels.count, column_values.count

      label2_hash = {
        color: label2.color,
        id: label2.id,
        name: label2.name,
        nameHtml: label2.name_html,
        url: label2.url,
      }

      assert_equal label2_hash, column_values.first
    end

    test "returns labels column data for a pull request" do
      label = create(:label, repository: @repo)
      @repo.update!(labels: [label])

      pull = create(
        :pull_request,
        :disable_disk_access,
        repository: @repo,
        user: @user,
      ).tap do |p|
        p.issue.add_labels([label])
        p.issue.save!
      end
      item = create(:memex_project_item, content: pull)

      assert_equal(
        [
          {
            color: label.color,
            id: label.id,
            name: label.name,
            nameHtml: label.name_html,
            url: label.url,
          }
        ],
        item.send(
          :special_type_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::LABELS_COLUMN_NAME),
          require_prefilled_associations: false
        )
      )
    end

    test "returns milestone column data for an issue" do
      milestone = create(:milestone, repository: @repo)
      issue = create(:issue, repository: @repo, milestone: milestone)
      item = create(:memex_project_item, content: issue)

      assert_equal(
        {
          id: milestone.id,
          number: milestone.number,
          state: milestone.state,
          title: milestone.title,
          url: "/#{milestone.repository.nwo}/milestone/#{milestone.number}",
          dueDate: milestone.due_date,
          repoNameWithOwner: milestone.repository.nwo,
        },
        item.send(
          :special_type_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::MILESTONE_COLUMN_NAME),
          require_prefilled_associations: false
        )
      )
    end

    test "returns milestone column data for a pull request" do
      milestone = create(:milestone, repository: @repo)

      pull = create(
        :pull_request,
        :disable_disk_access,
        repository: @repo,
        user: @user
      ).tap do |p|
        p.issue.milestone = milestone
        p.issue.save!
      end
      item = create(:memex_project_item, content: pull)

      assert_equal(
        {
          id: milestone.id,
          number: milestone.number,
          state: milestone.state,
          title: milestone.title,
          url: "/#{milestone.repository.nwo}/milestone/#{milestone.number}",
          dueDate: milestone.due_date,
          repoNameWithOwner: milestone.repository.nwo,
        },
        item.send(
          :special_type_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::MILESTONE_COLUMN_NAME),
          require_prefilled_associations: false
        )
      )
    end

    test "returns repository column data for a pull request" do
      pull = create(:pull_request, :disable_disk_access, repository: @repo, user: @user)
      item = create(:memex_project_item, content: pull)

      assert_equal(
        {
          id: @repo.id,
          isForked: false,
          isPublic: true,
          isArchived: @repo.archived?,
          hasIssues: @repo.has_issues?,
          name: @repo.name,
          nameWithOwner: @repo.nwo,
          url: @repo.permalink,
        },
        item.send(
          :special_type_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::REPOSITORY_COLUMN_NAME),
          require_prefilled_associations: false
        )
      )
    end

    test "returns repository column data for an issue" do
      issue = create(:issue, repository: @repo)
      item = create(:memex_project_item, content: issue)

      assert_equal(
        {
          id: @repo.id,
          isForked: false,
          isPublic: true,
          isArchived: @repo.archived?,
          hasIssues: @repo.has_issues?,
          name: @repo.name,
          nameWithOwner: @repo.nwo,
          url: @repo.permalink,
        },
        item.send(
          :special_type_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::REPOSITORY_COLUMN_NAME),
          require_prefilled_associations: false
        )
      )
    end

    test "returns parent issue column data for an issue" do
      Timecop.freeze do
        repository = create(:repository, owner: @org)
        memex = create(:memex_project, owner: @org)
        parent_issue = create(:issue, repository:, user: @org_admin)
        child_issue = create(:issue, repository:, user: @org_admin)
        parent_issue.add_sub_issue!(child_issue, @org_admin.id)

        item = create(:memex_project_item, memex_project: memex, content: child_issue)
        assert_equal(
          parent_issue.memex_column_hash,
          item.send(
            :special_type_column_value,
            MemexProjectColumn.default_column(MemexProjectColumn::PARENT_ISSUE_COLUMN_NAME),
            require_prefilled_associations: false
          )
        )
      end
    end

    test "returns nil for parent issue column for a pull request" do
      pull = create(:pull_request, :disable_disk_access, repository: @repo, user: @user)
      item = create(:memex_project_item, content: pull)

      assert_nil item.send(
        :special_type_column_value,
        MemexProjectColumn.default_column(MemexProjectColumn::PARENT_ISSUE_COLUMN_NAME),
        require_prefilled_associations: false
      )
    end

    test "returns sub-issues progress data for an issue" do
      repository = create(:repository, owner: @org)
      memex = create(:memex_project, owner: @org)
      parent_issue = create(:issue, repository:, user: @org_admin)
      child_issue = create(:issue, repository:, user: @org_admin)
      parent_issue.add_sub_issue!(child_issue, @org_admin.id)

      item = create(:memex_project_item, memex_project: memex, content: parent_issue)
      assert_equal(
        { total: 1, completed: 0, percentCompleted: 0 },
        item.send(
          :special_type_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::SUB_ISSUES_PROGRESS_COLUMN_NAME),
          require_prefilled_associations: false
        )
      )
    end

    test "returns nil for sub-issues progress column for a pull request" do
      pull = create(:pull_request, :disable_disk_access, repository: @repo, user: @user)
      item = create(:memex_project_item, content: pull)

      assert_nil item.send(
        :special_type_column_value,
        MemexProjectColumn.default_column(MemexProjectColumn::SUB_ISSUES_PROGRESS_COLUMN_NAME),
        require_prefilled_associations: false
      )
    end

    test "returns title column data for an issue" do
      issue = create(:issue, repository: @repo, title: "The Master Plan")
      item = create(:memex_project_item, content: issue)

      assert_equal(
        {
          number: issue.number,
          state: "open",
          stateReason: nil,
          title:
          {
            raw: "The Master Plan",
            html: "The Master Plan"
          },
          issueId: issue.id,
          url: issue.id_based_url
        },
        item.send(
          :special_type_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::TITLE_COLUMN_NAME)
        )
      )
    end

    test "returns title column with inline code fences for an issue" do
      issue = create(:issue, repository: @repo, title: "The `Master` Plan")
      item = create(:memex_project_item, content: issue)

      assert_equal(
        {
          number: issue.number,
          state: "open",
          stateReason: nil,
          title:
          {
            raw: "The `Master` Plan",
            html: "The <code>Master</code> Plan"
          },
          issueId: issue.id,
          url: issue.id_based_url
        },
        item.send(
          :special_type_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::TITLE_COLUMN_NAME)
        )
      )
    end

    test "returns title column data for a pull request" do
      pull = create(
        :pull_request,
        :disable_disk_access,
        repository: @repo,
        user: @user,
      ).tap do |p|
        p.issue.title = "The Antidote"
        p.issue.save!
      end
      item = create(:memex_project_item, content: pull)

      assert_equal(
        {
          number: pull.number,
          state: "open",
          isDraft: false,
          title: {
            raw: "The Antidote",
            html: "The Antidote"
          },
          issueId: pull.issue.id,
          url: pull.issue.id_based_url
        },
        item.send(
          :special_type_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::TITLE_COLUMN_NAME)
        )
      )
    end

    test "returns title column data with inline code fences for a pull request" do
      pull = create(
        :pull_request,
        :disable_disk_access,
        repository: @repo,
        user: @user,
      ).tap do |p|
        p.issue.title = "The `Antidote`"
        p.issue.save!
      end
      item = create(:memex_project_item, content: pull)

      assert_equal(
        {
          number: pull.number,
          state: "open",
          isDraft: false,
          title: {
            raw: "The `Antidote`",
            html: "The <code>Antidote</code>"
          },
          issueId: pull.issue.id,
          url: pull.issue.id_based_url
        },
        item.send(
          :special_type_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::TITLE_COLUMN_NAME)
        )
      )
    end

    test "returns title column data for a draft issue" do
      draft_issue = create(:draft_issue, title: "Fix `#123`")
      item = create(:memex_project_item, content: draft_issue)

      assert_equal(
        {
          title: {
            raw: "Fix `#123`",
            html: "Fix <code>#123</code>",
          }
        },
        item.send(
          :special_type_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::TITLE_COLUMN_NAME)
        )
      )
    end

    test "returns [] for empty assignee column of a draft issue" do
      draft_issue = create(:draft_issue)
      item = create(:memex_project_item, content: draft_issue)

      assert_equal [], item.send(
        :special_type_column_value,
        MemexProjectColumn.default_column(MemexProjectColumn::ASSIGNEES_COLUMN_NAME)
      )
    end

    test "returns nil for a labels column of a draft issue" do
      draft_issue = create(:draft_issue)
      item = create(:memex_project_item, content: draft_issue)

      assert_nil(
        item.send(
          :special_type_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::LABELS_COLUMN_NAME)
        )
      )
    end

    test "returns nil for a milestone column of a draft issue" do
      draft_issue = create(:draft_issue)
      item = create(:memex_project_item, content: draft_issue)

      assert_nil(
        item.send(
          :special_type_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::MILESTONE_COLUMN_NAME)
        )
      )
    end

    test "raises if we haven't provided prefilled associations for a column that needs it" \
      "except reviewers columns which do not apply to issues" do
      issue = create(:assigned_issue, repository: @repo)
      item = create(:memex_project_item, content: issue)

      columns_with_associations = MemexProjectColumn
        .default_columns
        .find_all do |c|
          c.special_type? && c.special_type_association.present? && !c.reviewers?
        end
      refute_empty columns_with_associations

      columns_with_associations.each do |column|
        assert_raises(Issue::MemexesDependency::AssociationRefused) do
          item.reload.send(:special_type_column_value, column)
        end
      end
    end

    test "#memex_special_type_column_value returns an empty array for reviewers columns" do
      issue = create(:assigned_issue, repository: @repo)
      item = create(:memex_project_item, content: issue)

      reviewers_column = item.memex_project.memex_project_columns.find(&:reviewers?)
      assert_equal [], item.content.memex_special_type_column_value(reviewers_column)
    end

    test "returns assignee column data when using the prefill_associations object" do
      # This adds the repository's owner as the assignee, which in this case is
      # @user.
      issue = create(:assigned_issue, repository: @repo)
      item = create(:memex_project_item, :with_denormalized_title, content: issue)

      assignees_column = item.memex_project.columns.find(&:assignees?)
      prefill_result = MemexProjectItemPrefiller.new(
        [item],
        columns: [assignees_column],
        read_denormalized_title: true,
        title_column: item.memex_project.columns.find(&:title?)
      ).prefill

      assignees_value = assert_max_query_count_per_table({ issues: 0, assignments: 0, users: 0 }) do
        item.send(:special_type_column_value, assignees_column, prefilled_associations: prefill_result)
      end

      assert_equal(
        [
          {
            avatarUrl: @user.primary_avatar_url(40),
            id: @user.id,
            login: @user.login,
            url: @user.permalink,
          },
        ],
        assignees_value
      )
    end

    test "returns label column data when using the prefill_associations object" do
      zebra_label = create(:label, repository: @repo, name: "Zebra")
      camel_label = create(:label, repository: @repo, name: "camel")
      @repo.update!(labels: [zebra_label, camel_label])

      issue = create(:issue, repository: @repo).tap do |i|
        i.add_labels([zebra_label, camel_label])
        i.save!
      end
      item = create(:memex_project_item, :with_denormalized_title, content: issue)

      labels_column = item.memex_project.columns.find(&:labels?)
      prefill_result = MemexProjectItemPrefiller.new(
        [item],
        columns: [labels_column],
        read_denormalized_title: true,
        title_column: item.memex_project.columns.find(&:title?)
      ).prefill

      labels_value = assert_max_query_count_per_table({ issues: 0, issues_labels: 0, labels: 0 }) do
        item.send(:special_type_column_value, labels_column, prefilled_associations: prefill_result)
      end

      assert_equal(
        [
          {
            color: camel_label.color,
            id: camel_label.id,
            name: "camel",
            nameHtml: "camel",
            url: camel_label.url,
          },
          {
            color: zebra_label.color,
            id: zebra_label.id,
            name: "Zebra",
            nameHtml: "Zebra",
            url: zebra_label.url,
          }
        ],
        labels_value
      )
    end

    test "returns milestone column data when using the prefill_associations object" do
      milestone = create(:milestone, repository: @repo)
      issue = create(:issue, repository: @repo, milestone: milestone)
      item = create(:memex_project_item, :with_denormalized_title, :with_denormalized_milestone, content: issue)

      milestone_column = item.memex_project.columns.find(&:milestone?)
      prefill_result = MemexProjectItemPrefiller.new(
        [item],
        columns: [milestone_column],
        read_denormalized_title: true,
        title_column: item.memex_project.columns.find(&:title?)
      ).prefill

      milestone_value = assert_max_query_count_per_table({ issues: 0, milestones: 0 }) do
        item.send(:special_type_column_value, milestone_column, prefilled_associations: prefill_result)
      end

      assert_equal(
        {
          id: milestone.id,
          number: milestone.number,
          state: milestone.state,
          title: milestone.title,
          url: "/#{milestone.repository.nwo}/milestone/#{milestone.number}",
          dueDate: milestone.due_date,
          repoNameWithOwner: milestone.repository.nwo,
        },
        milestone_value.symbolize_keys
      )
    end

    test "returns milestone column value data by default (if set)" do
      @memex = create(:memex_project)
      milestone = create(:milestone, repository: @repo)
      issue = create(:issue, repository: @repo, milestone: milestone)
      issue_2 = create(:issue, repository: @repo, milestone: milestone)
      item = create(:memex_project_item, :with_denormalized_title, :with_denormalized_milestone, content: issue, memex_project: @memex)
      item_without_milestone_value = create(:memex_project_item, :with_denormalized_title, content: issue_2, memex_project: @memex)

      milestone_column = item.memex_project.columns.find(&:milestone?)

      prefill_result = MemexProjectItemPrefiller.new(
        [item, item_without_milestone_value],
        columns: [milestone_column],
        read_denormalized_title: true,
        title_column: item.memex_project.columns.find(&:title?)
      ).prefill

      milestone_value = assert_max_query_count_per_table({ issues: 0, milestones: 0 }) do
        item.send(:special_type_column_value, milestone_column, prefilled_associations: prefill_result)
      end

      milestone_value_2 = assert_max_query_count_per_table({ issues: 0, milestones: 0 }) do
        item_without_milestone_value.send(:special_type_column_value, milestone_column, prefilled_associations: prefill_result)
      end

      assert_equal(
        {
          id: milestone.id,
          number: milestone.number,
          state: milestone.state,
          title: milestone.title,
          url: "/#{milestone.repository.nwo}/milestone/#{milestone.number}",
          dueDate: milestone.due_date,
          repoNameWithOwner: milestone.repository.nwo,
        },
        milestone_value.symbolize_keys
      )

      assert_nil milestone_value_2
    end

    test "returns repository column data when using the prefill_associations object" do
      issue = create(:issue, repository: @repo)
      item = create(:memex_project_item, :with_denormalized_title, content: issue)

      repository_column = item.memex_project.columns.find(&:repository?)
      prefill_result = MemexProjectItemPrefiller.new(
        [item],
        columns: [repository_column],
        read_denormalized_title: true,
        title_column: item.memex_project.columns.find(&:title?)
      ).prefill

      repository_value = assert_max_query_count_per_table({ issues: 0, repositories: 0 }) do
        item.send(:special_type_column_value, repository_column, prefilled_associations: prefill_result)
      end

      assert_equal(
        {
          id: @repo.id,
          isForked: false,
          isPublic: true,
          isArchived: @repo.archived?,
          hasIssues: @repo.has_issues?,
          name: @repo.name,
          nameWithOwner: @repo.nwo,
          url: @repo.permalink,
        },
        repository_value
      )
    end

    test "returns issue title data from denormalized source when using the prefill_associations object" do
      issue = create(:issue, repository: @repo, title: "The Master Plan")
      item = create(:memex_project_item, :with_denormalized_title, content: issue)
      title_column = item.memex_project.columns.find(&:title?)

      prefill_result = MemexProjectItemPrefiller.new(
        [item],
        columns: [title_column],
        read_denormalized_title: true,
        title_column: title_column
      ).prefill

      title_value = assert_max_query_count_per_table({ issues: 0 }) do
        item.send(:special_type_column_value, title_column, prefilled_associations: prefill_result)
      end

      assert_equal(
        {
          title: {
            raw: "The Master Plan",
            html: "The Master Plan"
          },
          number: issue.number,
          state: "open",
          stateReason: nil,
          issueId: issue.id,
          url: issue.id_based_url
        }.with_indifferent_access,
        title_value
      )
    end

    test "returns pull request title data from denormalized source when using the prefill_associations object" do
      pull = create(
        :pull_request,
        :disable_disk_access,
        repository: @repo,
        user: @user,
      ).tap do |p|
        p.issue.title = "The Antidote"
        p.issue.save!
      end
      item = create(:memex_project_item, :with_denormalized_title, content: pull)
      title_column = item.memex_project.columns.find(&:title?)

      prefill_result = MemexProjectItemPrefiller.new(
        [item],
        columns: [title_column],
        read_denormalized_title: true,
        title_column: title_column
      ).prefill

      title_value = assert_max_query_count_per_table({ issues: 0, pull_requests: 0 }) do
        item.send(:special_type_column_value, title_column, prefilled_associations: prefill_result)
      end

      assert_equal(
        {
          title: {
            raw: "The Antidote",
            html: "The Antidote"
          },
          number: pull.number,
          state: "open",
          isDraft: false,
          issueId: pull.issue.id,
          url: pull.issue.id_based_url
        }.with_indifferent_access,
        title_value
      )
    end

    test "returns draft issue title data from denormalized source when using the prefill_associations object" do
      draft_issue = create(:draft_issue, title: "Fix `#123`")
      item = create(:memex_project_item, :with_denormalized_title, content: draft_issue)
      title_column = item.memex_project.columns.find(&:title?)

      prefill_result = MemexProjectItemPrefiller.new(
        [item],
        columns: [title_column],
        read_denormalized_title: true,
        title_column: title_column
      ).prefill

      title_value = assert_max_query_count_per_table({ draft_issues: 0 }) do
        item.send(:special_type_column_value, title_column, prefilled_associations: prefill_result)
      end

      assert_equal(
        { title: { raw: "Fix `#123`", html: "Fix <code>#123</code>" } }.with_indifferent_access,
        title_value
      )
    end

    test "returns nil for a issue_type column of a draft issue" do
      memex = create(:memex_project, owner: @org)
      issue_type_column = memex.find_column_by_name_or_id(MemexProjectColumn::TYPE_COLUMN_NAME)
      draft_issue = create(:draft_issue)
      item = create(:memex_project_item, memex_project: memex, content: draft_issue)

      assert_nil(
        item.send(
          :special_type_column_value,
          issue_type_column,
        )
      )
    end

    test "returns issue_type column data when using the prefill_associations object" do
      enable_feature_flag(:issue_types, @org)
      memex = create(:memex_project, owner: @org)
      title_column = memex.columns.find(&:title?)
      issue_type_column = memex.find_column_by_name_or_id(MemexProjectColumn::TYPE_COLUMN_NAME)
      issue_type = create(:issue_type, owner: @org, name: "test", description: "")
      repository = create(:repository, owner: @org)
      issue = create(:issue, repository: repository, issue_type: issue_type)
      item = create(:memex_project_item, memex_project: memex, content: issue)

      prefill_result = MemexProjectItemPrefiller.new(
        [item],
        columns: [issue_type_column],
        read_denormalized_title: true,
        title_column: title_column,
      ).prefill

      issue_type_value = assert_max_query_count_per_table({ issue_types: 0, issues: 0, repositories: 0 }) do
        item.send(:special_type_column_value, issue_type_column, prefilled_associations: prefill_result)
      end

      assert_equal(
        {
          id: issue_type.id,
          name: issue_type.name,
          description: issue_type.description,
          color: issue_type.color.upcase,
        },
        issue_type_value
      )
    end

    test "returns issue_type column data when prefill_associations object is not present" do
      enable_feature_flag(:issue_types, @org)
      memex = create(:memex_project, owner: @org)
      title_column = memex.columns.find(&:title?)
      issue_type_column = memex.find_column_by_name_or_id(MemexProjectColumn::TYPE_COLUMN_NAME)
      issue_type = create(:issue_type, owner: @org, name: "test", description: "")
      repository = create(:repository, owner: @org)
      issue = create(:issue, repository: repository, issue_type: issue_type)
      item = create(:memex_project_item, memex_project: memex, content: issue)

      prefill_result = MemexProjectItemPrefiller.new(
        [item],
        columns: [issue_type_column],
        read_denormalized_title: true,
        title_column: title_column,
      ).prefill

      issue_type_value = assert_max_query_count_per_table({ issue_types: 0, issues: 0, repositories: 0 }) do
        item.send(:special_type_column_value, issue_type_column, prefilled_associations: prefill_result)
      end

      assert_equal(
        {
          id: issue_type.id,
          name: issue_type.name,
          description: issue_type.description,
          color: issue_type.color.upcase,
        },
        issue_type_value
      )
    end
  end

  context "#generic_type_column_value" do
    test "returns nil if a value does not exist" do
      assert_nil(
        @item.send(:generic_type_column_value, @text_column, require_prefilled_associations: false)
      )
    end

    test "raises if we haven't prefilled `memex_project_column_values` association" do
      assert_raises(MemexProjectItem::ColumnDependency::AssociationRefused) do
        @item.send(:generic_type_column_value, @text_column)
      end
    end

    test "retrieves a text value where it exists" do
      value = create(
        :memex_project_column_value,
        value: "wrong value",
        json_value: { raw: "foo", html: "foo" },
        memex_project_column: @text_column,
        memex_project_item: @item,
      )

      assert_equal(
        value.json_value,
        @item.send(
          :generic_type_column_value,
          @text_column,
          require_prefilled_associations: false,
        )
      )
    end

    test "retrieves a date value where it exists" do
      value = create(
        :memex_project_column_value,
        value: "2021-02-02T00:00:00+00:00",
        json_value: { value: "2021-01-01T00:00:00+00:00" },
        memex_project_column: @date_column,
        memex_project_item: @item,
      )

      assert_equal(
        value.json_value,
        @item.send(
          :generic_type_column_value,
          @date_column,
          require_prefilled_associations: false,
        )
      )
    end

    test "retrieves a number value where it exists" do
      value = create(
        :memex_project_column_value,
        value: 1,
        json_value: { value: 2 },
        memex_project_column: @number_column,
        memex_project_item: @item,
      )

      assert_equal(
        value.json_value,
        @item.send(
          :generic_type_column_value,
          @number_column,
          require_prefilled_associations: false,
        )
      )
    end

    test "retrieves a single-select value where it exists" do
      column = create(
        :single_select_memex_column,
        name: "Celebrations",
        memex_project: @memex,
        settings: {
          options: [
            { id: "aaaaaaaa", name: "wins :tada:", color: "BLUE", description: "winning" },
            { id: "bbbbbbbb", name: "wrong value", color: "PURPLE", description: "wrong" },
          ]
        }
      )

      value = create(
        :memex_project_column_value,
        value: "bbbbbbbb",
        json_value: { id: "aaaaaaaa" },
        memex_project_column: column,
        memex_project_item: @item,
      )

      assert_equal(
        value.json_value,
        @item.send(
          :generic_type_column_value,
          column,
          require_prefilled_associations: false,
        )
      )
    end
  end

  context "#set_column_value" do
    test "sets errors on the item when updating the underlying issue title fails" do
      title_column = @memex.find_column_by_name_or_id(MemexProjectColumn::TITLE_COLUMN_NAME)
      refute_nil title_column
      item = create(:memex_project_item, memex_project: @memex, content: @issue)

      fake_errors = stub(full_messages: ["o noes", "dear me"])
      Issue.any_instance.stubs(:update).returns(false)
      Issue.any_instance.stubs(:errors).returns(fake_errors)

      result = item.set_column_value(title_column, { title: "My new title" }, @user)

      refute result
      assert_equal ["o noes and dear me"], item.errors.full_messages
    end

    test "sets errors on the item when updating the assignees on the underlying content fails" do
      rando = create(:verified_user)
      repo = create(:private_repository, owner: @user)
      issue = create(:issue, repository: repo, user: @user)
      item = create(:memex_project_item, content: issue)
      memex = item.memex_project
      assignees_column = memex.find_column_by_name_or_id(MemexProjectColumn::ASSIGNEES_COLUMN_NAME)
      refute_nil assignees_column

      result = item.set_column_value(assignees_column, [rando.id], rando)

      refute result
      assert_equal ["Could not be assigned to #{rando.display_login}."], item.errors.full_messages
    end

    test "sets errors on the item when only some of the assignees can be set on the underlying content" do
      rando = create(:verified_user, login: "rando")
      repo = create(:private_repository, owner: @user)
      issue = create(:issue, repository: repo, user: @user)
      refute_includes issue.available_assignee_ids, rando.id, "need a user who can't be an assignee"
      item = create(:memex_project_item, content: issue)
      memex = item.memex_project
      assignees_column = memex.find_column_by_name_or_id(MemexProjectColumn::ASSIGNEES_COLUMN_NAME)
      refute_nil assignees_column

      result = item.set_column_value(assignees_column, [@user.id, rando.id], @user)

      refute result
      assert_equal ["Could not be assigned to #{@user.display_login} and #{rando.display_login}."],
        item.errors.full_messages
    end

    test "sets errors on the item when updating value for single-select column fails" do
      result = @item.set_column_value(@single_select_column, "invalid", @user)

      refute result
      assert_equal ["Column value must be a valid value for single_select column"], @item.errors.full_messages
    end

    test "sets errors on the item when updating value for iteration column fails" do
      refute @item.set_column_value(@iteration_column, "invalid", @user)
      assert_equal ["Column value must be a valid value for iteration column"], @item.errors.full_messages
    end

    test "sets errors on the item when setting an invalid milestone on the underlying content" do
      item = create(:memex_project_item, content: @issue, memex_project: @memex)
      random_milestone = create(:milestone, repository: create(:repository))
      milestone_column = @memex.find_column_by_name_or_id(MemexProjectColumn::MILESTONE_COLUMN_NAME)
      refute_nil milestone_column

      # Returns false and sets error if invalid milestone
      refute item.set_column_value(milestone_column, random_milestone.id, @user)
      assert_equal ["Milestone does not exist"], item.errors.full_messages
    end

    test "sets errors on the item when setting an issue type for disabled issue type" do
      memex = create(:memex_project, owner: @org)
      issue_type = create(:issue_type, owner: @org, name: "test")
      issue_type_column = memex.find_column_by_name_or_id(MemexProjectColumn::TYPE_COLUMN_NAME)
      repository = create(:repository, owner: @org)
      repository.add_member(@user, action: :write)

      enable_feature_flag(:issue_types, @org)
      issue = create(:issue, repository: repository)
      item = create(:memex_project_item, memex_project: memex, content: issue)
      @org.issue_types.first.update(enabled: false)

      # Returns false and sets error if invalid issue_type
      refute item.set_column_value(issue_type_column, @org.issue_types.first.id, @user)
      assert_equal ["Issue type is not enabled"], item.errors.full_messages
    end

    test "sets errors on the item when setting an invalid issue type on the underlying content" do
      different_org = create(:organization)
      random_issue_type = create(:issue_type, owner: different_org, name: "test")
      memex = create(:memex_project, owner: @org)
      issue_type_column = memex.find_column_by_name_or_id(MemexProjectColumn::TYPE_COLUMN_NAME)
      repository = create(:repository, owner: @org)
      enable_feature_flag(:issue_types, @org)
      issue = create(:issue, repository: repository)
      item = create(:memex_project_item, memex_project: memex, content: issue)

      # Returns false and sets error if issue type does not belong to the same org as the memex
      refute_equal random_issue_type.owner, @memex.owner
      refute item.set_column_value(issue_type_column, random_issue_type.id, @org_admin)
      assert_equal ["Issue type cannot be found in this organization"], item.errors.full_messages
    end

    test "sets errors on the item when setting an issue type without permission to set the type" do
      memex = create(:memex_project, owner: @org)
      issue_type = create(:issue_type, owner: @org, name: "test")
      issue_type_column = memex.find_column_by_name_or_id(MemexProjectColumn::TYPE_COLUMN_NAME)
      repository = create(:repository, owner: @org)
      repository.add_member(@user, action: :read)

      enable_feature_flag(:issue_types, @org)
      issue = create(:issue, repository: repository)
      item = create(:memex_project_item, memex_project: memex, content: issue)

      # Returns false as @user only has read access
      refute item.set_column_value(issue_type_column, @org.issue_types.first.id, @user)
      assert_equal ["You do not have permission to set the issue type for this item"], item.errors.full_messages
    end

    test "sets errors on the item when updating the underlying content's milestone fails" do
      item = create(:memex_project_item, content: @issue, memex_project: @memex)
      milestone = create(:milestone, repository: @repo)
      milestone_column = @memex.find_column_by_name_or_id(MemexProjectColumn::MILESTONE_COLUMN_NAME)
      refute_nil milestone_column

      fake_errors = stub(full_messages: ["o noes", "dear me"])
      Issue.any_instance.stubs(:update).returns(false)
      Issue.any_instance.stubs(:errors).returns(fake_errors)

      # Returns false and sets error if invalid milestone
      refute item.set_column_value(milestone_column, milestone.id, @user)
      assert_equal ["o noes and dear me"], item.errors.full_messages
    end

    test "sets an error on the item if unable to set an invalid label on the underlying content" do
      item = create(:memex_project_item, content: @issue, memex_project: @memex)
      invalid_label = create(:label, repository: create(:repository))
      label_column = @memex.find_column_by_name_or_id(MemexProjectColumn::LABELS_COLUMN_NAME)
      refute_nil label_column
      assert_empty item.column_value(label_column, require_prefilled_associations: false)

      result = item.set_column_value(label_column, [invalid_label.id], @user)

      refute result
      assert_equal ["Not all labels could be found"], item.errors.full_messages
      assert_empty item.column_value(label_column, require_prefilled_associations: false)
    end

    test "sets an error on the item if unable to set any labels on the underlying content" do
      item = create(:memex_project_item, content: @issue, memex_project: @memex)
      valid_label = create(:label, repository: @repo)
      label_column = @memex.find_column_by_name_or_id(MemexProjectColumn::LABELS_COLUMN_NAME)
      refute_nil label_column
      assert_empty item.column_value(label_column, require_prefilled_associations: false)

      fake_errors = stub(full_messages: ["o noes", "dear me"])
      Issue.any_instance.stubs(:errors).returns(fake_errors)
      Issue.any_instance.stubs(:replace_labels).returns(false)

      result = item.set_column_value(label_column, [valid_label.id], @user)

      refute result
      assert_equal ["o noes and dear me"], item.errors.full_messages
      assert_empty item.column_value(label_column, require_prefilled_associations: false)
    end

    context "with a tracked_by column with markdown at rest" do
      test "reject adding a child issue to parent issue, tasklist_block disabled" do
        enable_feature_flag(:tasklist_block_markdown_at_rest)
        disable_feature_flag(:tasklist_block)

        memex = create(:memex_project)
        owner = memex.owner
        tracked_by_column = memex.columns.find(&:tracked_by?)
        child_memex_project_item_issue = create(:memex_project_item, memex_project: memex, content: @issue)
        parent_issue = create(:issue, repository: @repo)
        child_memex_project_item_draft = @draft_item

        refute child_memex_project_item_issue.set_column_value(tracked_by_column,
          ["#{@repo.nwo}##{parent_issue.number}"], owner)
        refute child_memex_project_item_draft.set_column_value(tracked_by_column,
          ["#{@repo.nwo}##{parent_issue.number}"], owner)
      end

      test "reject adding child to parent when child is pr" do
        enable_feature_flag(:tasklist_block_markdown_at_rest)
        enable_feature_flag(:tasklist_block)

        memex = create(:memex_project)
        owner = memex.owner
        tracked_by_column = memex.columns.find(&:tracked_by?)
        pull = create(:pull_request, :disable_disk_access, user: @user, repository: @repo)
        child_memex_project_item_pr = create(:memex_project_item, memex_project: memex, content: pull)
        parent_issue = create(:issue, repository: @repo)

        GitHub.issues_graph_api_client.stubs(:get_tracking_blocks_by_parent)
          .returns(ErrorMock.new(error: nil, data: DataMock.new(blocks: [])))
        refute child_memex_project_item_pr.set_column_value(tracked_by_column,
          ["#{@repo.nwo}##{parent_issue.number}"], owner)
      end

      test "allows adding a child issue to parent issue when parent issue has no tasklists" do
        enable_feature_flag(:tasklist_block_markdown_at_rest)
        enable_feature_flag(:tasklist_block)

        memex = create(:memex_project)
        owner = memex.owner
        tracked_by_column = memex.columns.find(&:tracked_by?)
        child_memex_project_item_issue = create(:memex_project_item, memex_project: memex, content: @issue)
        parent_issue = create(:issue, repository: @repo)
        child_memex_project_item_draft = @draft_item

        GitHub.issues_graph_api_client.stubs(:get_tracking_blocks_by_parent)
          .returns(ErrorMock.new(error: nil, data: DataMock.new(blocks: [])))

        assert child_memex_project_item_issue.set_column_value(tracked_by_column,
          ["#{@repo.nwo}##{parent_issue.number}"], owner)
        refute child_memex_project_item_draft.set_column_value(tracked_by_column,
          ["#{@repo.nwo}##{parent_issue.number}"], owner)
      end

      test "allows adding a child issue to parent issue when parent issue has tasklists" do
        enable_feature_flag(:tasklist_block_markdown_at_rest)
        enable_feature_flag(:tasklist_block)

        memex = create(:memex_project)
        owner = memex.owner
        tracked_by_column = memex.columns.find(&:tracked_by?)
        tasklist_body = <<~MD
    ```[tasklist]
    ### title
    - [ ] item 1
    ```
        MD
        parent_issue = create(:issue, repository: @repo, body: tasklist_body)
        child_memex_project_item_issue = create(:memex_project_item, memex_project: memex, content: @issue)

        assert child_memex_project_item_issue.set_column_value(tracked_by_column,
          ["#{@repo.nwo}##{parent_issue.number}"], owner)
        expected_parent_body = <<~MD
        ```[tasklist]
        ### title
        - [ ] item 1
        - [ ] #{@issue.url}
        ```
        MD
        assert_equal expected_parent_body.squish, parent_issue.reload.body.squish
      end

      test "allows adding and removing a child issue from parent issue when append_only isn't sent" do
        enable_feature_flag(:tasklist_block)
        enable_feature_flag(:issue_hierarchy_state)
        enable_feature_flag(:tasklist_block_markdown_at_rest)
        disable_feature_flag(:issue_tasklist_block_writes)
        disable_feature_flag(:issues_graph_api_concurrent_faraday)
        disable_feature_flag(:issues_graph_api_disable_denormalized_read)

        memex = create(:memex_project)
        owner = memex.owner
        tracked_by_column = memex.columns.find(&:tracked_by?)

        parent_body = <<~MD
        ```[tasklist]
        - [ ] ##{@issue.number}
        ```
        MD

        parent_issue = create(:issue, repository: @repo, body: parent_body)
        new_parent_issue = create(:issue, repository: @repo, body: "")
        # create(:issue_link, source_issue: parent_issue, target_issue: @issue, link_type: :track)

        key = IssuesGraph::Proto::Key.new(itemId: parent_issue.id)
        tracked_issue = IssuesGraph::Proto::Issue.new(key: key, repoId: parent_issue.repository_id,
          number: parent_issue.number)
        tracking_block = IssuesGraph::Proto::TrackingBlock.new(name: "Tracking", issues: [tracked_issue])
        get_issue_response = IssuesGraph::Proto::GetIssueResponse.new(trackedBy: [tracking_block])
        get_issue_result = ::IssuesGraph::Result.success(get_issue_response)
        issue_graph_client = mock("issue_graph_client")
        GitHub.stubs(:issues_graph_api_client_strict).returns(issue_graph_client)
        issue_graph_client.expects(:get_issue).returns(get_issue_result)

        child_memex_project_item_issue = create(:memex_project_item, memex_project: memex, content: @issue)

        assert child_memex_project_item_issue.set_column_value(tracked_by_column,
          ["#{new_parent_issue.repository.nwo}##{new_parent_issue.number}"], owner)
        expected_parent_body = <<~MD
        ```[tasklist]
        ```
        MD
        expected_new_parent_body = <<~MD
        ```[tasklist]
        - [ ] #{@issue.url}
        ```
        MD
        assert_equal expected_parent_body, parent_issue.reload.body
        assert_equal expected_new_parent_body.squish, new_parent_issue.reload.body.squish
      end

      test "allows only adding a child issue when append_only is true" do
        enable_feature_flag(:tasklist_block)
        enable_feature_flag(:issue_hierarchy_state)
        enable_feature_flag(:tasklist_block_markdown_at_rest)
        disable_feature_flag(:issue_tasklist_block_writes)
        disable_feature_flag(:issues_graph_api_concurrent_faraday)
        disable_feature_flag(:issues_graph_api_disable_denormalized_read)

        memex = create(:memex_project)
        owner = memex.owner
        tracked_by_column = memex.columns.find(&:tracked_by?)

        parent_body = <<~MD
        ```[tasklist]
        - [ ] ##{@issue.number}
        ```
        MD

        parent_issue = create(:issue, repository: @repo, body: parent_body)
        new_parent_issue = create(:issue, repository: @repo, body: "")

        key = IssuesGraph::Proto::Key.new(itemId: parent_issue.id)
        tracked_issue = IssuesGraph::Proto::Issue.new(key: key, repoId: parent_issue.repository_id,
          number: parent_issue.number)
        tracking_block = IssuesGraph::Proto::TrackingBlock.new(name: "Tracking", issues: [tracked_issue])
        get_issue_response = IssuesGraph::Proto::GetIssueResponse.new(trackedBy: [tracking_block])
        get_issue_result = ::IssuesGraph::Result.success(get_issue_response)
        issue_graph_client = mock("issue_graph_client")
        GitHub.stubs(:issues_graph_api_client_strict).returns(issue_graph_client)
        issue_graph_client.expects(:get_issue).returns(get_issue_result)

        child_memex_project_item_issue = create(:memex_project_item, memex_project: memex, content: @issue)

        assert child_memex_project_item_issue.set_column_value(tracked_by_column,
          ["#{new_parent_issue.repository.nwo}##{new_parent_issue.number}"], owner, true)
        expected_new_parent_body = <<~MD
        ```[tasklist]
        - [ ] #{@issue.url}
        ```
        MD
        # original parent_issue body should be unchanged
        assert_equal parent_body, parent_issue.reload.body
        assert_equal expected_new_parent_body.squish, new_parent_issue.reload.body.squish
      end
    end

    context "with a tracked_by column w/o markdown at rest" do
      test "reject adding a child issue to parent issue, tasklist_block disabled" do
        disable_feature_flag(:tasklist_block)
        disable_feature_flag(:tasklist_block_markdown_at_rest)

        memex = create(:memex_project)
        owner = memex.owner
        tracked_by_column = memex.columns.find(&:tracked_by?)
        child_memex_project_item_issue = create(:memex_project_item, memex_project: memex, content: @issue)
        parent_issue = create(:issue, repository: @repo)
        child_memex_project_item_draft = @draft_item

        refute child_memex_project_item_issue.set_column_value(tracked_by_column,
          ["#{@repo.nwo}##{parent_issue.number}"], owner)
        refute child_memex_project_item_draft.set_column_value(tracked_by_column,
          ["#{@repo.nwo}##{parent_issue.number}"], owner)
      end

      test "allows adding a child issue to parent issue when parent issue has no tasklists" do
        enable_feature_flag(:tasklist_block)
        disable_feature_flag(:tasklist_block_markdown_at_rest)

        memex = create(:memex_project)
        owner = memex.owner
        tracked_by_column = memex.columns.find(&:tracked_by?)
        child_memex_project_item_issue = create(:memex_project_item, memex_project: memex, content: @issue)
        parent_issue = create(:issue, repository: @repo)
        child_memex_project_item_draft = @draft_item

        add_tracking_block_result = ::IssuesGraph::Result.success(
          ::IssuesGraph::Proto::AddTrackingBlockResponse.new(primaryKeys: [])
        )
        GitHub.issues_graph_api_client.stubs(:add_tracking_block_for_parent).returns(add_tracking_block_result)

        get_tracking_block_result = ::IssuesGraph::Result.success(
          ::IssuesGraph::Proto::GetTrackingBlocksResponse.new(blocks: [])
        )
        GitHub.issues_graph_api_client.stubs(:get_tracking_blocks_by_parent).returns(get_tracking_block_result)

        assert child_memex_project_item_issue.set_column_value(tracked_by_column,
          ["#{@repo.nwo}##{parent_issue.number}"], owner)
        refute child_memex_project_item_draft.set_column_value(tracked_by_column,
          ["#{@repo.nwo}##{parent_issue.number}"], owner)
      end

      test "allows adding a child issue to parent issue when parent issue has tasklists" do
        enable_feature_flag(:tasklist_block)
        disable_feature_flag(:tasklist_block_markdown_at_rest)

        memex = create(:memex_project)
        owner = memex.owner
        tracked_by_column = memex.columns.find(&:tracked_by?)
        parent_issue = create(:issue, repository: @repo)
        child_memex_project_item_issue = create(:memex_project_item, memex_project: memex, content: @issue)
        block_id = SecureRandom.uuid
        block_key = IssuesGraph::Proto::Key.new(ownerId: owner.id,
          primaryKey: IssuesGraph::Proto::PrimaryKey.new(uuid: block_id))
        tracking_block = IssuesGraph::Proto::TrackingBlock.new(
          key: block_key
        )
        tracking_block_response = IssuesGraph::Proto::GetTrackingBlockResponse.new(block: tracking_block,
          success: true)

        get_tracking_blocks_result = ::IssuesGraph::Result.success(
          ::IssuesGraph::Proto::GetTrackingBlocksResponse.new(blocks: [tracking_block])
        )
        update_tracking_block_result = ::IssuesGraph::Result.success(tracking_block_response)

        GitHub.issues_graph_api_client.stubs(:get_tracking_blocks_by_parent).returns(get_tracking_blocks_result)
        GitHub.issues_graph_api_client.stubs(:update_tracking_block_by_key).returns(update_tracking_block_result)

        assert child_memex_project_item_issue.set_column_value(tracked_by_column,
          ["#{@repo.nwo}##{parent_issue.number}"], owner)
      end

      test "allows removing a child issue to parent issue" do
        enable_feature_flag(:tasklist_block)
        enable_feature_flag(:issues_graph_api_concurrent_faraday, @repo)
        disable_feature_flag(:issues_graph_api_disable_denormalized_read)
        disable_feature_flag(:tasklist_block_markdown_at_rest)

        memex = create(:memex_project)
        owner = memex.owner
        tracked_by_column = memex.columns.find(&:tracked_by?)

        parent_issue = create(:issue, repository: @repo)
        create(:issue_link, source_issue: parent_issue, target_issue: @issue, link_type: :track)
        child_memex_project_item_issue = create(:memex_project_item, memex_project: memex, content: @issue)
        block_id = SecureRandom.uuid
        block_key = IssuesGraph::Proto::Key.new(ownerId: owner.id,
          primaryKey: IssuesGraph::Proto::PrimaryKey.new(uuid: block_id))
        issue_key = IssuesGraph::Proto::Key.new(ownerId: owner.id, itemId: @issue.id,
          primaryKey: IssuesGraph::Proto::PrimaryKey.new(uuid: SecureRandom.uuid))
        tracking_block = IssuesGraph::Proto::TrackingBlock.new(
          key: block_key,
          issues: [{ **@issue.to_hierarchy_model, key: issue_key }]
        )
        tracking_block_issue_removed = IssuesGraph::Proto::TrackingBlock.new(
          key: block_key
        )
        tracking_block_response = IssuesGraph::Proto::GetTrackingBlockResponse.new(
          block: tracking_block_issue_removed,
          success: true,
        )
        object = mock
        object.expects(:data).returns(tracking_block_response)

        GitHub.issues_graph_api_client.stubs(:get_tracking_blocks_by_parent)
          .returns(ErrorMock.new(error: nil, data: DataMock.new(blocks: [tracking_block])))
        GitHub.issues_graph_api_client.expects(:update_tracking_block_by_key).once.returns(object)

        assert_equal parent_issue.id, @issue.normalized_tracking_issues(viewer: owner)[0][:issue_id]
        assert child_memex_project_item_issue.set_column_value(tracked_by_column, [], owner)
      end

      test "does not remove a child issue from parent issue if append_only is true" do
        enable_feature_flag(:tasklist_block)
        enable_feature_flag(:issues_graph_api_concurrent_faraday, @repo)
        disable_feature_flag(:issues_graph_api_disable_denormalized_read)
        disable_feature_flag(:tasklist_block_markdown_at_rest)

        memex = create(:memex_project)
        owner = memex.owner
        tracked_by_column = memex.columns.find(&:tracked_by?)

        parent_issue = create(:issue, repository: @repo)
        create(:issue_link, source_issue: parent_issue, target_issue: @issue, link_type: :track)
        child_memex_project_item_issue = create(:memex_project_item, memex_project: memex, content: @issue)

        assert_equal parent_issue.id, @issue.normalized_tracking_issues(viewer: owner)[0][:issue_id]

        assert child_memex_project_item_issue.set_column_value(tracked_by_column, [], owner, true)
      end
    end
  end

  context "#set_column_value" do
    test "can set the title of an issue item" do
      issue = create(:issue, title: "Fix this")
      item = create(:memex_project_item, content: issue)
      new_title = "Fix this `code`!"
      title_column = item.memex_project.find_column_by_name_or_id(MemexProjectColumn::TITLE_COLUMN_NAME)

      # Make sure `set_column_value` returns a truthy value to indicate success.
      assert item.set_column_value(title_column, { title: new_title }, @user)

      # Then, make sure we updated the canonical table.
      assert_equal "Fix this `code`!", issue.reload.title

      # Finally, make sure we copied the data to `memex_project_column_values`.
      title_value = item.memex_project_column_values.find_by(memex_project_column_id: title_column.id)
      assert_equal(
        {
          "title" => {
            "raw" => "Fix this `code`!",
            "html" => "Fix this <code>code</code>!",
          },
          "number" => issue.number,
          "state" => issue.state.to_s,
          "url" => "#{GitHub.url}/#{issue.repository.owner_id}/#{issue.repository.id}/issues/#{issue.number}",
          "issueId" => issue.id,
          "stateReason" => issue.state_reason&.to_s,
        },
        title_value.json_value
      )
    end

    test "can set the title of a pull request item" do
      pull = create(:pull_request, :disable_disk_access).tap { |p| p.issue.update!(title: "Fixes `code`") }
      item = create(:memex_project_item, content: pull)
      new_title = "Fixes `code` and more!"
      title_column = item.memex_project.find_column_by_name_or_id(MemexProjectColumn::TITLE_COLUMN_NAME)

      # Make sure `set_column_value` returns a truthy value to indicate success.
      assert item.set_column_value(title_column, { title: new_title }, @user)

      # Then, make sure we updated the canonical table.
      assert_equal "Fixes `code` and more!", pull.reload.title

      # Finally, make sure we copied the data to `memex_project_column_values`.
      title_value = item.memex_project_column_values.find_by(memex_project_column_id: title_column.id)
      assert_equal(
        {
          "title" => {
            "raw" => "Fixes `code` and more!",
            "html" => "Fixes <code>code</code> and more!",
          },
          "number" => pull.number,
          "state" => pull.state.to_s,
          "url" => "#{GitHub.url}/#{pull.repository.owner_id}/#{pull.repository.id}/pull/#{pull.number}",
          "issueId" => pull.issue.id,
          "isDraft" => false,
        },
        title_value.json_value
      )
    end

    test "can set the title of a draft issue item" do
      draft_issue = create(:draft_issue, title: "github")
      item = create(:memex_project_item, content: draft_issue)
      new_title = "Fix `#123`"
      title_column = item.memex_project.find_column_by_name_or_id(MemexProjectColumn::TITLE_COLUMN_NAME)

      # Make sure `set_column_value` returns a truthy value to indicate success.
      assert item.set_column_value(title_column, { title: new_title }, @user)

      # Then, make sure we updated the canonical table.
      assert_equal new_title, draft_issue.reload.title

      # Finally, make sure we copied the data to `memex_project_column_values`.
      title_value = item.memex_project_column_values.find_by(memex_project_column_id: title_column.id)
      assert_equal(
        {
          "title" => {
            "raw" => new_title,
            "html" => "Fix <code>#123</code>",
          }
        },
        title_value.json_value
      )
    end

    context "when suppress_hydro_events: true" do
      test "suppresses column value update hydro events" do
        column_value = create(
          :single_select_memex_project_column_value,
          value: @single_select_options[0]["id"],
          memex_project_column: @single_select_column,
          memex_project_item: @item
        )
        assert_equal 1, @item.memex_project_column_values.count

        assert_difference("@item.memex_project_column_values.count", 0) do
          assert @item.set_column_value(@single_select_column, @single_select_options[2]["id"], @user, suppress_hydro_events: true)
        end

        assert_equal @single_select_options[2]["id"], @item.memex_project_column_values.first.value
        assert_equal(
          { "id" => @single_select_options[2]["id"] },
          @item.memex_project_column_values.first.json_value
        )
        assert_hydro_messages(count: 0, schema: "github.memex.v0.MemexProjectColumnValueUpdate")
      end

      test "suppresses column value destroy hydro events" do
        column_value = create(
          :single_select_memex_project_column_value,
          value: @single_select_options[0]["id"],
          memex_project_column: @single_select_column,
          memex_project_item: @item
        )
        assert_equal 1, @item.memex_project_column_values.count

        assert_difference("@item.memex_project_column_values.count", -1) do
          assert @item.set_column_value(@single_select_column, nil, @user, suppress_hydro_events: true)
        end

        assert @item.memex_project_column_values.empty?
        assert_hydro_messages(count: 0, schema: "github.memex.v0.MemexProjectColumnValueDestroy")
      end

      test "suppresses column value create hydro events" do
        assert_equal 0, @item.memex_project_column_values.count

        assert_difference("@item.memex_project_column_values.count", 1) do
          assert @item.set_column_value(@single_select_column, @single_select_options[0]["id"], @user, suppress_hydro_events: true)
        end

        assert_equal @single_select_options[0]["id"], @item.memex_project_column_values.first.value
        assert_equal(
          { "id" => @single_select_options[0]["id"] },
          @item.memex_project_column_values.first.json_value
        )
        assert_hydro_messages(count: 0, schema: "github.memex.v0.MemexProjectColumnValueCreate")
      end
    end


    test "triggers the IssueUpdate Hydro event due to setting the title of an issue item" do
      GitHub.context.push(actor_id: @user.id)

      now = Time.now.beginning_of_day

      travel_to(now) do
        old_title = "Fix this"
        new_title = "Fix this `code`!"
        issue = create(:issue, title: old_title)
        item = create(:memex_project_item, content: issue)
        title_column = item.memex_project.columns.find(&:title?)
        expected_hydro_message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          actor: Hydro::EntitySerializer.user(@user),
          repository: Hydro::EntitySerializer.repository(issue.repository),
          repository_owner: Hydro::EntitySerializer.user(issue.repository.owner),
          issue: Hydro::EntitySerializer.issue(issue),
          pull_request: nil,
          previous_title: old_title,
          current_title: new_title,
          previous_body: issue.body,
          current_body: issue.body,
          specimen_body: Hydro::EntitySerializer.specimen_data(issue.body),
          specimen_title: Hydro::EntitySerializer.specimen_data(new_title),
        }

        assert item.set_column_value(title_column, { title: new_title }, @user)

        with_hydro_publisher(GitHub.hydro_publisher) do
          assert_hydro_published(expected_hydro_message, schema: "github.v2.IssueUpdate", count: 1)
        end
      end
    end

    test "triggers the IssueUpdate Hydro event due to setting the title of a pull request item" do
      GitHub.context.push(actor_id: @user.id)

      now = Time.now.beginning_of_day

      travel_to(now) do
        old_title = "Fixes `code`"
        new_title = "Fixes `code` and more!"
        pull = create(:pull_request, :disable_disk_access).tap { |p| p.issue.update_column(:title, old_title) }
        item = create(:memex_project_item, content: pull)
        title_column = item.memex_project.columns.find(&:title?)
        expected_hydro_message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          actor: Hydro::EntitySerializer.user(@user),
          repository: Hydro::EntitySerializer.repository(pull.repository),
          repository_owner: Hydro::EntitySerializer.user(pull.repository.owner),
          issue: Hydro::EntitySerializer.issue(pull.issue),
          pull_request: Hydro::EntitySerializer.pull_request(pull),
          previous_title: old_title,
          current_title: new_title,
          previous_body: pull.body,
          current_body: pull.body,
          specimen_body: Hydro::EntitySerializer.specimen_data(pull.body),
          specimen_title: Hydro::EntitySerializer.specimen_data(new_title),
        }

        assert item.set_column_value(title_column, { title: new_title }, @user)

        with_hydro_publisher(GitHub.hydro_publisher) do
          assert_hydro_published(expected_hydro_message, schema: "github.v2.IssueUpdate", count: 1)
        end
      end
    end

    test "does not clear an item's title if given nil as the value of the title column" do
      issue = create(:issue)
      item = create(:memex_project_item, content: issue)
      title_column = item.memex_project.find_column_by_name_or_id(MemexProjectColumn::TITLE_COLUMN_NAME)
      original_title = issue.title
      original_title_value_json = {
        "title" => {
          "raw" => issue.title,
          "html" => issue.title,
        },
        "number" => issue.number,
        "state" => issue.state.to_s,
        "url" => issue.permalink,
        "issueId" => issue.id,
        "isDraft" => false,
      }
      title_value = create(:memex_project_column_value, item: item, column: title_column,
        json_value: original_title_value_json)

      # Make sure `set_column_value` returns a falsey value to indicate failure.
      refute item.set_column_value(title_column, { title: nil }, @user)

      # Then, make sure the canonical data did not change.
      assert_equal original_title, issue.reload.title

      # Finally, make sure the denormalized copy of the data did not change.
      assert_equal original_title_value_json.stringify_keys, title_value.reload.json_value
    end

    test "can set the value of a text column for the first time" do
      refute @item.memex_project_column_values.any?

      assert_difference("@item.memex_project_column_values.count", 1) do
        assert @item.set_column_value(@text_column, "https://github.com", @user)
      end

      assert_equal "https://github.com", @item.memex_project_column_values.first.value
      assert_equal(
        {
          "raw" => "https://github.com",
          "html" => %Q(<a href="https://github.com">https://github.com</a>)
        },
        @item.memex_project_column_values.first.json_value
      )
    end

    test "can update the value of a text column" do
      create(
        :memex_project_column_value,
        value: "foo",
        memex_project_column: @text_column,
        memex_project_item: @item
      )
      assert_equal 1, @item.memex_project_column_values.count

      assert_difference("@item.memex_project_column_values.count", 0) do
        assert @item.set_column_value(@text_column, "bar", @user)
      end

      assert_equal "bar", @item.memex_project_column_values.first.value
      assert_equal(
        {
          "raw" => "bar",
          "html" => "bar"
        },
        @item.memex_project_column_values.first.json_value
      )
    end

    test "can clear the value of a text column" do
      create(:memex_project_column_value, value: "foo", memex_project_column: @text_column, memex_project_item: @item)
      assert_equal 1, @item.memex_project_column_values.count

      assert_difference("@item.memex_project_column_values.count", -1) do
        assert @item.set_column_value(@text_column, "", @user)
      end
    end

    test "can set the value of an iteration column for the first time" do
      refute @item.memex_project_column_values.any?

      assert_difference("@item.memex_project_column_values.count", 1) do
        assert @item.set_column_value(@iteration_column, @iteration_options[0]["id"], @user)
      end

      assert_equal @iteration_options[0]["id"], @item.memex_project_column_values.first.value
      assert_equal(
        { "id" => @iteration_options[0]["id"] },
        @item.memex_project_column_values.first.json_value
      )
    end

    test "can update the value of a iteration column" do
      create(
        :iteration_memex_project_column_value,
        value: @iteration_options[0]["id"],
        memex_project_column: @iteration_column,
        memex_project_item: @item
      )
      assert_equal 1, @item.memex_project_column_values.count

      assert_difference("@item.memex_project_column_values.count", 0) do
        assert @item.set_column_value(@iteration_column, @iteration_options[1]["id"], @user)
      end

      assert_equal @iteration_options[1]["id"], @item.memex_project_column_values.first.value
      assert_equal(
        { "id" => @iteration_options[1]["id"] },
        @item.memex_project_column_values.first.json_value
      )
    end

    test "can clear the value of a iteration column" do
      create(
        :iteration_memex_project_column_value,
        value: @iteration_options[0]["id"],
        memex_project_column: @iteration_column,
        memex_project_item: @item
      )
      assert_equal 1, @item.memex_project_column_values.count

      assert_difference("@item.memex_project_column_values.count", -1) do
        assert @item.set_column_value(@iteration_column, "", @user)
      end

      assert_empty @item.reload.memex_project_column_values
    end

    test "cannot set the value of a iteration column to an invalid value" do
      create(
        :iteration_memex_project_column_value,
        value: @iteration_options[0]["id"],
        memex_project_column: @iteration_column,
        memex_project_item: @item
      )
      assert_equal 1, @item.memex_project_column_values.count

      refute @item.set_column_value(@iteration_column, "large", @user)
      assert_includes @item.errors.full_messages, "Column value must be a valid value for iteration column"
    end

    test "can set the value of a single_select column for the first time" do
      refute @item.memex_project_column_values.any?

      assert_difference("@item.memex_project_column_values.count", 1) do
        assert @item.set_column_value(@single_select_column, @single_select_options[0]["id"], @user)
      end

      assert_equal @single_select_options[0]["id"], @item.memex_project_column_values.first.value
      assert_equal(
        { "id" => @single_select_options[0]["id"] },
        @item.memex_project_column_values.first.json_value
      )
    end

    test "can update the value of a single_select column" do
      create(
        :single_select_memex_project_column_value,
        value: @single_select_options[0]["id"],
        memex_project_column: @single_select_column,
        memex_project_item: @item
      )
      assert_equal 1, @item.memex_project_column_values.count

      assert_difference("@item.memex_project_column_values.count", 0) do
        assert @item.set_column_value(@single_select_column, @single_select_options[2]["id"], @user)
      end

      assert_equal @single_select_options[2]["id"], @item.memex_project_column_values.first.value
      assert_equal(
        { "id" => @single_select_options[2]["id"] },
        @item.memex_project_column_values.first.json_value
      )
    end

    test "can clear the value of a single_select column" do
      create(
        :single_select_memex_project_column_value,
        value: @single_select_options[0]["id"],
        memex_project_column: @single_select_column,
        memex_project_item: @item
      )
      assert_equal 1, @item.memex_project_column_values.count

      assert_difference("@item.memex_project_column_values.count", -1) do
        assert @item.set_column_value(@single_select_column, "", @user)
      end

      assert_empty @item.reload.memex_project_column_values
    end

    test "cannot set the value of a single_select column to an invalid value" do
      create(
        :single_select_memex_project_column_value,
        value: @single_select_options[0]["id"],
        memex_project_column: @single_select_column,
        memex_project_item: @item
      )
      assert_equal 1, @item.memex_project_column_values.count

      refute @item.set_column_value(@single_select_column, "large", @user)
      assert_includes @item.errors.full_messages, "Column value must be a valid value for single_select column"
    end

    test "can set the value of a number column for the first time" do
      refute @item.memex_project_column_values.any?

      assert_difference("@item.memex_project_column_values.count", 1) do
        assert @item.set_column_value(@number_column, 1, @user)
      end

      assert_equal "1", @item.memex_project_column_values.first.value
      assert_equal(
        { "value" => 1 },
        @item.memex_project_column_values.first.json_value
      )
    end

    test "can support different numeric formats" do
      refute @item.memex_project_column_values.any?

      assert_difference("@item.memex_project_column_values.count", 1) do
        assert @item.set_column_value(@number_column, 1, @user)
      end

      assert_equal "1", @item.memex_project_column_values.first.value

      assert_difference("@item.memex_project_column_values.count", 0) do
        assert @item.set_column_value(@number_column, 1E4, @user)
      end

      assert_equal "10000.0", @item.memex_project_column_values.first.value

      assert_difference("@item.memex_project_column_values.count", 0) do
        assert @item.set_column_value(@number_column, 0.75, @user)
      end

      assert_equal "0.75", @item.memex_project_column_values.first.value
    end

    test "can update the value of a number column" do
      create(
        :number_memex_project_column_value,
        value: 1,
        memex_project_column: @number_column,
        memex_project_item: @item
      )
      assert_equal 1, @item.memex_project_column_values.count

      assert_difference("@item.memex_project_column_values.count", 0) do
        assert @item.set_column_value(@number_column, 10, @user)
      end

      assert_equal "10", @item.memex_project_column_values.first.value
      assert_equal(
        { "value" => 10 },
        @item.memex_project_column_values.first.json_value
      )
    end

    test "can clear the value of a number column" do
      create(
        :number_memex_project_column_value,
        value: 1,
        memex_project_column: @number_column,
        memex_project_item: @item
      )
      assert_equal 1, @item.memex_project_column_values.count

      assert_difference("@item.memex_project_column_values.count", -1) do
        assert @item.set_column_value(@number_column, nil, @user)
      end
    end

    test "cannot set the value of a number column to an invalid value" do
      refute @item.memex_project_column_values.any?

      refute @item.set_column_value(@number_column, "bogus value", @user)
      assert_includes @item.errors.full_messages, "Column value must be a valid value for number column"
    end

    test "can set the value of a date column for the first time, and formats it in iso" do
      refute @item.memex_project_column_values.any?

      assert_difference("@item.memex_project_column_values.count", 1) do
        assert @item.set_column_value(@date_column, "2021-01-01", @user)
      end

      assert_equal "2021-01-01T00:00:00+00:00", @item.memex_project_column_values.first.value
      assert_equal(
        { "value" => "2021-01-01T00:00:00+00:00" },
        @item.memex_project_column_values.first.json_value
      )
    end

    test "can update the value of a date column" do
      create(
        :date_memex_project_column_value,
        value: "2021-01-01",
        memex_project_column: @date_column,
        memex_project_item: @item
      )
      assert_equal 1, @item.memex_project_column_values.count

      assert_difference("@item.memex_project_column_values.count", 0) do
        assert @item.set_column_value(@date_column, "2021-02-01T00:00:00+00:00", @user)
      end

      assert_equal "2021-02-01T00:00:00+00:00", @item.memex_project_column_values.first.value
      assert_equal(
        { "value" => "2021-02-01T00:00:00+00:00" },
        @item.memex_project_column_values.first.json_value
      )
    end

    test "can clear the value of a date column" do
      create(
        :date_memex_project_column_value,
        value: "2021-01-01",
        memex_project_column: @date_column,
        memex_project_item: @item
      )
      assert_equal 1, @item.memex_project_column_values.count

      assert_difference("@item.memex_project_column_values.count", -1) do
        assert @item.set_column_value(@date_column, nil, @user)
      end
    end

    test "cannot set the value of a date column to an invalid value" do
      refute @item.memex_project_column_values.any?

      refute @item.set_column_value(@date_column, "bogus value", @user)
      assert_includes @item.errors.full_messages, "Column value must be a valid value for date column"
    end

    test "can update assignees for an issue" do
      issue = create(:issue)
      item = create(:memex_project_item, content: issue)
      refute_equal issue.user, @user

      issue.assignees = [@user]

      assert item.set_column_value(MemexProjectColumn.default_column("Assignees"), [issue.user.id], @user)
      assert_equal [issue.user], issue.reload.assignees
    end

    test "can update assignees for a pull request" do
      pull = create(:pull_request, :disable_disk_access)
      item = create(:memex_project_item, content: pull)
      refute_equal pull.user, @user

      pull.issue.assignees = [@user]

      assert item.set_column_value(MemexProjectColumn.default_column("Assignees"), [pull.user.id], @user)
      assert_equal [pull.user], pull.reload.assignees
    end

    test "can update assignees for a draft issue" do
      draft_issue = create(:draft_issue)
      item = create(:memex_project_item, content: draft_issue)

      assert item.set_column_value(MemexProjectColumn.default_column("Assignees"), [@user.id], @user)
      assert_equal [@user], draft_issue.reload.assignees
    end

    test "can update labels for an issue" do
      issue = create(:issue)
      item = create(:memex_project_item, content: issue)
      label = issue.repository.labels.create(name: "carrot")

      assert item.set_column_value(MemexProjectColumn.default_column("Labels"), [label.id], @user)
      assert_equal [label], issue.reload.labels
    end

    test "can update labels for a pull request" do
      pull = create(:pull_request, :disable_disk_access)
      item = create(:memex_project_item, content: pull)
      label = pull.repository.labels.create(name: "carrot")

      assert item.set_column_value(MemexProjectColumn.default_column("Labels"), [label.id], @user)
      assert_equal [label], pull.reload.labels
    end

    test "cannot update labels for a draft issue" do
      draft_issue = create(:draft_issue)
      item = create(:memex_project_item, content: draft_issue)

      refute item.set_column_value(MemexProjectColumn.default_column("Labels"), [1], @user)
    end

    test "can add a milestone for an issue" do
      issue = create(:issue)
      item = create(:memex_project_item, content: issue)
      milestone = create(:milestone, repository: issue.repository)
      milestone_column = item.memex_project.find_column_by_name_or_id(MemexProjectColumn::MILESTONE_COLUMN_NAME)

      # Make sure `set_column_value` returns a truthy value to indicate success.
      assert item.set_column_value(milestone_column, milestone.id, @user)

      # Then, make sure we updated the canonical table.
      assert_equal milestone.id, issue.reload.milestone_id

      # Finally, make sure we copied the data to `memex_project_column_values`.
      assert_memex_item_milestone_is_denormalized(item.memex_project, item)
    end

    test "can set the issue type for an issue" do
      memex = create(:memex_project, owner: @org)
      issue_type = create(:issue_type, owner: @org, name: "test")
      issue_type_column = memex.find_column_by_name_or_id(MemexProjectColumn::TYPE_COLUMN_NAME)
      repository = create(:repository, owner: @org)
      enable_feature_flag(:issue_types, @org)
      issue = create(:issue, repository: repository)
      item = create(:memex_project_item, memex_project: memex, content: issue)

      assert_changes -> { issue.reload.issue_type_id }, from: nil, to: issue_type.id do
        assert item.set_column_value(issue_type_column, issue_type.id, @org_admin)
      end
    end

    test "can remove the issue type for an issue" do
      memex = create(:memex_project, owner: @org)
      issue_type = create(:issue_type, owner: @org, name: "test")
      issue_type_column = memex.find_column_by_name_or_id(MemexProjectColumn::TYPE_COLUMN_NAME)
      repository = create(:repository, owner: @org)
      enable_feature_flag(:issue_types, @org)
      issue = create(:issue, repository: repository, issue_type: issue_type)
      item = create(:memex_project_item, memex_project: memex, content: issue)

      assert_changes -> { issue.reload.issue_type_id }, from: issue_type.id, to: nil do
        assert item.set_column_value(issue_type_column, nil, @org_admin)
      end
    end

    test "cannot set issue type for a pull request" do
      memex = create(:memex_project, owner: @org)
      issue_type = create(:issue_type, owner: @org, name: "test")
      issue_type_column = memex.find_column_by_name_or_id(MemexProjectColumn::TYPE_COLUMN_NAME)
      repository = create(:repository, owner: @org)
      enable_feature_flag(:issue_types, @org)
      pull_request = create(:pull_request, :disable_disk_access, repository: repository)
      item = create(:memex_project_item, memex_project: memex, content: pull_request)

      assert_no_changes -> { pull_request.issue.reload.issue_type_id } do
        refute item.set_column_value(issue_type_column, issue_type.id, @org_admin)
      end
    end

    test "cannot set issue type for a draft issue" do
      memex = create(:memex_project, owner: @org)
      issue_type = create(:issue_type, owner: @org, name: "test")
      issue_type_column = memex.find_column_by_name_or_id(MemexProjectColumn::TYPE_COLUMN_NAME)
      repository = create(:repository, owner: @org)
      enable_feature_flag(:issue_types, @org)
      draft_issue = create(:draft_issue)
      item = create(:memex_project_item, memex_project: memex, content: draft_issue)

      refute item.set_column_value(issue_type_column, issue_type.id, @org_admin)
    end

    test "can set the parent issue for an issue" do
      memex = create(:memex_project, owner: @org)
      parent_issue_column = memex.find_column_by_name_or_id(MemexProjectColumn::PARENT_ISSUE_COLUMN_NAME)

      enable_feature_flag(:sub_issues)

      repository = create(:repository, owner: @org)
      parent_issue = create(:issue, repository: repository)
      child_issue = create(:issue, repository: repository)

      parent_item = create(:memex_project_item, memex_project: memex, content: parent_issue)
      child_item = create(:memex_project_item, memex_project: memex, content: child_issue)

      assert child_item.set_column_value(parent_issue_column, parent_issue.id, @org_admin)

      parent_issue.recalculate_sub_issue_list!

      assert_equal 1, parent_issue.sub_issue_list.total
    end

    test "can remove the parent issue for an issue" do
      memex = create(:memex_project, owner: @org)
      parent_issue_column = memex.find_column_by_name_or_id(MemexProjectColumn::PARENT_ISSUE_COLUMN_NAME)

      enable_feature_flag(:sub_issues)

      repository = create(:repository, owner: @org)

      parent_issue = create(:issue, repository: repository)
      child_issue1 = create(:issue, repository: repository)
      child_issue2 = create(:issue, repository: repository)
      child_issue3 = create(:issue, repository: repository)

      parent_issue.add_sub_issue!(child_issue1, @org_admin.id)
      parent_issue.add_sub_issue!(child_issue2, @org_admin.id)
      parent_issue.add_sub_issue!(child_issue3, @org_admin.id)

      raise "Parent issue not created" unless parent_issue.present?

      parent_item = create(:memex_project_item, memex_project: memex, content: parent_issue)
      child_item1 = create(:memex_project_item, memex_project: memex, content: child_issue1)
      child_item2 = create(:memex_project_item, memex_project: memex, content: child_issue2)
      child_item3 = create(:memex_project_item, memex_project: memex, content: child_issue3)

      parent_issue.recalculate_sub_issue_list!
      assert_equal 3, parent_issue.sub_issue_list.total

      assert child_item1.set_column_value(parent_issue_column, "", @org_admin)

      parent_issue.reload.recalculate_sub_issue_list!
      assert_equal 2, parent_issue.sub_issue_list.total
    end

    test "gracefully handles removing parent issue when issue does not have a parent" do
      memex = create(:memex_project, owner: @org)
      parent_issue_column = memex.find_column_by_name_or_id(MemexProjectColumn::PARENT_ISSUE_COLUMN_NAME)

      enable_feature_flag(:sub_issues)

      repository = create(:repository, owner: @org)

      parent_issue = create(:issue, repository: repository)
      child_issue1 = create(:issue, repository: repository)
      child_issue2 = create(:issue, repository: repository)
      child_issue3 = create(:issue, repository: repository)

      parent_issue.add_sub_issue!(child_issue1, @org_admin.id)
      parent_issue.add_sub_issue!(child_issue2, @org_admin.id)
      parent_issue.add_sub_issue!(child_issue3, @org_admin.id)

      raise "Parent issue not created" unless parent_issue.present?

      parent_item = create(:memex_project_item, memex_project: memex, content: parent_issue)
      child_item1 = create(:memex_project_item, memex_project: memex, content: child_issue1)
      child_item2 = create(:memex_project_item, memex_project: memex, content: child_issue2)
      child_item3 = create(:memex_project_item, memex_project: memex, content: child_issue3)

      parent_issue.recalculate_sub_issue_list!
      assert_equal 3, parent_issue.sub_issue_list.total

      # Remove the parent issue from the child being edited before
      # the column is updated to simulate a missing parent issue
      parent_issue.remove_sub_issue!(child_issue1)

      assert child_item1.set_column_value(parent_issue_column, "", @org_admin)

      parent_issue.reload.recalculate_sub_issue_list!
      assert_equal 2, parent_issue.sub_issue_list.total
    end

    test "cannot set the parent issue for a draft issue" do
      memex = create(:memex_project, owner: @org)
      parent_issue_column = memex.find_column_by_name_or_id(MemexProjectColumn::PARENT_ISSUE_COLUMN_NAME)

      enable_feature_flag(:sub_issues)

      draft_issue = create(:draft_issue)

      repository = create(:repository, owner: @org)
      parent_issue = create(:issue, repository: repository)

      parent_item = create(:memex_project_item, memex_project: memex, content: parent_issue)
      child_item = create(:memex_project_item, memex_project: memex, content: draft_issue)

      assert_nil parent_issue.sub_issue_list

      refute child_item.set_column_value(parent_issue_column, parent_issue.id, @org_admin)

      parent_issue.recalculate_sub_issue_list!
      assert_equal 0, parent_issue.sub_issue_list.total
    end

    test "cannot set the parent issue for a pull request" do
      memex = create(:memex_project, owner: @org)
      parent_issue_column = memex.find_column_by_name_or_id(MemexProjectColumn::PARENT_ISSUE_COLUMN_NAME)

      enable_feature_flag(:sub_issues)

      pull_request = create(:pull_request, :disable_disk_access)
      parent_issue = create(:issue)

      parent_item = create(:memex_project_item, memex_project: memex, content: parent_issue)
      child_item = create(:memex_project_item, memex_project: memex, content: pull_request)

      assert_nil parent_issue.sub_issue_list

      refute child_item.set_column_value(parent_issue_column, parent_issue.id, @org_admin)

      parent_issue.recalculate_sub_issue_list!
      assert_equal 0, parent_issue.sub_issue_list.total
    end

    test "cannot add self as sub-issue" do
      memex = create(:memex_project, owner: @org)
      parent_issue_column = memex.find_column_by_name_or_id(MemexProjectColumn::PARENT_ISSUE_COLUMN_NAME)

      enable_feature_flag(:sub_issues)

      parent_issue = create(:issue)
      parent_item = create(:memex_project_item, memex_project: memex, content: parent_issue)

      assert_nil parent_issue.sub_issue_list

      refute parent_item.set_column_value(parent_issue_column, parent_issue.id, @org_admin)

      parent_issue.recalculate_sub_issue_list!
      assert_equal 0, parent_issue.sub_issue_list.total

      assert_includes parent_item.errors.full_messages, "Sub issue cannot be the same as the parent issue"
    end

    test "fails if parent issue doesn't exist" do
      memex = create(:memex_project, owner: @org)
      parent_issue_column = memex.find_column_by_name_or_id(MemexProjectColumn::PARENT_ISSUE_COLUMN_NAME)

      enable_feature_flag(:sub_issues)

      parent_issue = create(:issue)
      child_issue = create(:issue)

      parent_item = create(:memex_project_item, memex_project: memex, content: parent_issue)
      child_item = create(:memex_project_item, memex_project: memex, content: child_issue)

      parent_issue.destroy!
      assert_nil parent_issue.sub_issue_list

      refute child_item.set_column_value(parent_issue_column, parent_issue.id, @org_admin)

      parent_issue.recalculate_sub_issue_list!
      assert_equal 0, parent_issue.sub_issue_list.total

      assert_includes child_item.errors.full_messages, "Parent issue does not exist"
    end

    test "fails if parent issue has sub-issues past the breadth limit" do
      repo = create(:repository)
      memex = create(:memex_project, owner: @org)
      parent_issue_column = memex.find_column_by_name_or_id(MemexProjectColumn::PARENT_ISSUE_COLUMN_NAME)

      enable_feature_flag(:sub_issues)

      parent_issue = create(:issue, repository: repo)
      parent_item = create(:memex_project_item, memex_project: memex, content: parent_issue)
      child = create(:issue, repository: repo)
      parent_issue.add_sub_issue!(child, @user.id)

      child_past_limit = create(:issue, repository: repo)
      child_item = create(:memex_project_item, memex_project: memex, content: child_past_limit)
      SubIssue.stub_const(:MAXIMUM_BREADTH, 1) do
        refute child_item.set_column_value(parent_issue_column, parent_issue.id, @org_admin)
      end

      assert_includes child_item.errors.full_messages, "Parent cannot have more than 1 sub-issues"
    end

    test "fails when sub-issue height is exceeded" do
      repo = create(:repository)
      memex = create(:memex_project, owner: @org)
      parent_issue_column = memex.find_column_by_name_or_id(MemexProjectColumn::PARENT_ISSUE_COLUMN_NAME)

      enable_feature_flag(:sub_issues)

      issues = create_hierarchy!("
      - parent
        - child 1
          - child 2
            - child 3
              - child 4
                - child 5
                  - child 6
                    - child 7
      ", repository: repo)

      assert_equal 7, issues["parent"]&.sub_issue_list&.height
      heights = issues.transform_values { |issue| issue.reload.sub_issue_list&.height }
      expected_heights = {
        "parent" => 7,
        "child 1" => 6,
        "child 2" => 5,
        "child 3" => 4,
        "child 4" => 3,
        "child 5" => 2,
        "child 6" => 1,
        "child 7" => nil,
      }
      assert_equal expected_heights, heights

      parent_issue = issues["parent"]
      parent_item = create(:memex_project_item, memex_project: memex, content: parent_issue)

      child_issue = create(:issue, repository: repo)
      child_item = create(:memex_project_item, memex_project: memex, content: child_issue)
      refute parent_item.set_column_value(parent_issue_column, child_issue&.id, @org_admin)
      assert_includes parent_item.errors.full_messages, "You can’t add more than 7 layers of sub-issues. To add a sub-issue, remove a parent issue at any level."
    end

    test "fails when creating a circular reference" do
      repo = create(:repository)
      memex = create(:memex_project, owner: @org)
      parent_issue_column = memex.find_column_by_name_or_id(MemexProjectColumn::PARENT_ISSUE_COLUMN_NAME)

      enable_feature_flag(:sub_issues)

      parent_issue = create(:issue, repository: repo)
      parent_item = create(:memex_project_item, memex_project: memex, content: parent_issue)

      child1 = create(:issue, repository: repo)
      parent_issue.add_sub_issue!(child1, @user.id)
      child2 = create(:issue, repository: repo)
      child1.add_sub_issue!(child2, @user.id)
      child3 = create(:issue, repository: repo)
      child2.add_sub_issue!(child3, @user.id)
      child3_item = create(:memex_project_item, memex_project: memex, content: child3)

      refute parent_item.set_column_value(parent_issue_column, child3.id, @org_admin)

      assert_includes parent_item.errors.full_messages, "Sub issue may not create a circular dependency"
    end

    test "can remove a milestone for an issue" do
      milestone = create(:milestone)
      issue = create(:issue, repository: milestone.repository, milestone: milestone)
      item = create(:memex_project_item, content: issue)
      milestone_column = item.memex_project.find_column_by_name_or_id(MemexProjectColumn::MILESTONE_COLUMN_NAME)
      column_value = create(:milestone_column_value, memex_project_item: item, memex_project_column: milestone_column,
        value: milestone.id, json_value: {
        type: "Milestone", value: milestone.memex_column_hash.stringify_keys
      })

      # Make sure the row in the `memex_project_column_values` exists before we try to clear the milestone
      assert_memex_item_milestone_is_denormalized(item.memex_project, item)

      assert item.set_column_value(milestone_column, "", @user)
      assert_nil issue.reload.milestone_id

      # Make sure the row in the `memex_project_column_values` table is no longer there
      refute_memex_item_milestone_is_denormalized(item.memex_project, item)
    end

    test "can add a milestone for a pull request" do
      pull = create(:pull_request, :disable_disk_access)
      item = create(:memex_project_item, content: pull)
      milestone = create(:milestone, repository: pull.repository)

      milestone_column = item.memex_project.find_column_by_name_or_id(MemexProjectColumn::MILESTONE_COLUMN_NAME)

      assert item.set_column_value(milestone_column, milestone.id, @user)
      assert_equal milestone.id, pull.issue.reload.milestone_id
    end

    test "can remove a milestone for a pull request" do
      milestone = create(:milestone)
      issue = create(:issue, repository: milestone.repository, milestone: milestone)
      pull = create(:pull_request, :disable_disk_access, repository: milestone.repository, issue: issue)
      item = create(:memex_project_item, content: pull)

      milestone_column = item.memex_project.find_column_by_name_or_id(MemexProjectColumn::MILESTONE_COLUMN_NAME)

      assert item.set_column_value(milestone_column, "", @user)
      assert_nil pull.issue.reload.milestone_id
    end

    test "cannot add a milestone for a draft issue" do
      milestone = create(:milestone)
      draft_issue = create(:draft_issue)
      item = create(:memex_project_item, content: draft_issue)

      milestone_column = item.memex_project.find_column_by_name_or_id(MemexProjectColumn::MILESTONE_COLUMN_NAME)

      refute item.set_column_value(milestone_column, milestone.id, @user)
    end

    test "returns false when a milestone cannot be found" do
      milestone = create(:milestone)
      issue = create(:issue, repository: milestone.repository)
      item = create(:memex_project_item, content: issue)

      milestone_id = milestone.id
      assert milestone.destroy!

      milestone_column = item.memex_project.find_column_by_name_or_id(MemexProjectColumn::MILESTONE_COLUMN_NAME)

      refute item.set_column_value(milestone_column, milestone_id, @user)
    end

    test "returns false for a column with an unsupported data type" do
      issue = create(:issue)
      item = create(:memex_project_item, content: issue)

      refute item.set_column_value(
        MemexProjectColumn.default_column("Repository"),
        issue.repository_id,
        @user
      )
    end

    test "updates field values in both MySQL and Elasticsearch" do
      enable_feature_flag(:memex_sync_write_to_es, @item.memex_project)
      single_select_field = @single_select_column.to_field

      populate_elasticsearch_index!([@item])

      assert_empty @item.memex_project_column_values.to_a
      assert_nil elasticsearch_field_value(@item, single_select_field)

      result = @item.set_column_value(@single_select_column, @single_select_options[0]["id"], @user, skip_elasticsearch_updates: false)

      @item.reload

      # Verify that result is accurately reported.
      assert result.is_a?(MemexProjectColumn::Interface::Writeable::Result)
      assert result.mysql.succeeded?
      assert result.elasticsearch.succeeded?

      # Verify that MySQL values have been updated.
      assert_equal @single_select_options[0]["id"], @item.memex_project_column_values.where(memex_project_column_id: @single_select_column.id).first.value

      # Verify that Elasticsearch values have been updated.
      assert_equal @single_select_options[0].slice("id", "name"), elasticsearch_field_value(@item, single_select_field)
    end
  end

  context "#clear_column_value" do
    test "does not clear an item's title for title column and returns false" do
      issue = create(:issue)
      item = create(:memex_project_item, content: issue)
      title_column = item.memex_project.find_column_by_name_or_id(MemexProjectColumn::TITLE_COLUMN_NAME)
      original_title = issue.title
      original_title_value_json = {
        "title" => {
          "raw" => issue.title,
          "html" => issue.title,
        },
        "number" => issue.number,
        "state" => issue.state.to_s,
        "url" => issue.permalink,
        "issueId" => issue.id,
        "isDraft" => false,
      }
      title_value = create(:memex_project_column_value, item: item, column: title_column,
        json_value: original_title_value_json)

      # Make sure `set_column_value` returns a falsey value to indicate failure.
      refute item.clear_column_value(title_column, @user)

      # Then, make sure the canonical data did not change.
      assert_equal original_title, issue.reload.title

      # Finally, make sure the denormalized copy of the data did not change.
      assert_equal original_title_value_json.stringify_keys, title_value.reload.json_value
    end

    test "can clear the value of a text column" do
      create(:memex_project_column_value, value: "foo", memex_project_column: @text_column, memex_project_item: @item)
      assert_equal 1, @item.memex_project_column_values.count

      assert_difference("@item.memex_project_column_values.count", -1) do
        assert @item.clear_column_value(@text_column, @user)
      end

      assert_empty @item.reload.memex_project_column_values
    end

    test "clears the value of a iteration column" do
      create(
        :iteration_memex_project_column_value,
        value: @iteration_options[0]["id"],
        memex_project_column: @iteration_column,
        memex_project_item: @item
      )
      assert_equal 1, @item.memex_project_column_values.count

      assert_difference("@item.memex_project_column_values.count", -1) do
        assert @item.clear_column_value(@iteration_column, @user)
      end

      assert_empty @item.reload.memex_project_column_values
    end

    test "clears the value of a single_select column" do
      create(
        :single_select_memex_project_column_value,
        value: @single_select_options[0]["id"],
        memex_project_column: @single_select_column,
        memex_project_item: @item
      )
      assert_equal 1, @item.memex_project_column_values.count

      assert_difference("@item.memex_project_column_values.count", -1) do
        assert @item.clear_column_value(@single_select_column, @user)
      end

      assert_empty @item.reload.memex_project_column_values
    end

    test "removes a milestone for an issue" do
      milestone = create(:milestone)
      issue = create(:issue, repository: milestone.repository, milestone: milestone)
      item = create(:memex_project_item, content: issue)
      milestone_column = item.memex_project.find_column_by_name_or_id(MemexProjectColumn::MILESTONE_COLUMN_NAME)
      column_value = create(:milestone_column_value, memex_project_item: item, memex_project_column: milestone_column,
        value: milestone.id, json_value: {
        type: "Milestone", value: milestone.memex_column_hash.stringify_keys
      })

      # Make sure the row in the `memex_project_column_values` exists before trying to clear the milestone
      assert_memex_item_milestone_is_denormalized(item.memex_project, item)

      assert item.clear_column_value(milestone_column, @user)
      assert_nil issue.reload.milestone_id

      # Make sure the row in the `memex_project_column_values` table was erased
      refute_memex_item_milestone_is_denormalized(item.memex_project, item)
    end

    test "clears the value of a number column" do
      create(
        :number_memex_project_column_value,
        value: 1,
        memex_project_column: @number_column,
        memex_project_item: @item
      )
      assert_equal 1, @item.memex_project_column_values.count

      assert_difference("@item.memex_project_column_values.count", -1) do
        assert @item.clear_column_value(@number_column, @user)
      end

      assert_empty @item.reload.memex_project_column_values
    end

    test "clears the value of a date column" do
      create(
        :date_memex_project_column_value,
        value: "2021-01-01",
        memex_project_column: @date_column,
        memex_project_item: @item
      )
      assert_equal 1, @item.memex_project_column_values.count

      assert_difference("@item.memex_project_column_values.count", -1) do
        assert @item.set_column_value(@date_column, nil, @user)
      end

      assert_empty @item.reload.memex_project_column_values
    end

    test "removes labels from an issue" do
      issue = create(:issue)
      label = issue.repository.labels.create(name: "carrot")
      issue.replace_labels([label])
      item = create(:memex_project_item, content: issue)

      refute_equal(issue.labels.count, 0)
      assert_equal(label.id, issue.labels[0].id)

      assert item.clear_column_value(MemexProjectColumn.default_column("Labels"), @user)
      assert_empty issue.reload.labels
    end
  end

  context "#queue_set_column_values" do
    test "when setting multiple columns without a persisted project item, it should not enqueue" do
      issue = create(:issue)
      item = @memex.build_item(creator: @user, issue_or_pull: issue)

      MemexProjectItemSetColumnsJob.expects(:perform_later).never
      item.queue_set_column_values([], @user)
    end

    test "when attempting to set an empty list of columns to a persisted project's item, it should not enqueue" do
      issue = create(:issue)
      item = create(:memex_project_item, content: issue)

      MemexProjectItemSetColumnsJob.expects(:perform_later).never
      item.queue_set_column_values([], @user)
    end

    test "when the list of columns is nil with a persisted project's item, it should not enqueue" do
      issue = create(:issue)
      item = create(:memex_project_item, content: issue)

      MemexProjectItemSetColumnsJob.expects(:perform_later).never
      item.queue_set_column_values(nil, @user)
    end

    test "it should enqueue a job to set values for each column" do
      issue = create(:issue)
      item = create(:memex_project_item, content: issue)

      columns = [
        { column: @text_column, value: "This will take weeks!" },
        { column: @number_column, value: 1 }
      ]

      MemexProjectItemSetColumnsJob.expects(:perform_later).once.with(
        item.id, columns, @user.id
      )

      item.queue_set_column_values(columns, @user)
    end
  end

  test "destroys associated column values in the background" do
    item = create(:memex_project_item)
    status_column = item.memex_project.status_column
    assert_equal "single_select", status_column&.data_type

    assert item.set_column_value(status_column, status_column.settings["options"].first["id"], @user)
    refute_empty MemexProjectColumnValue.where(memex_project_item_id: item.id)

    perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { item.destroy! }

    assert_empty MemexProjectColumnValue.where(memex_project_item_id: item.id)
  end
end
