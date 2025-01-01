# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectItem::CsvColumnDependencyTest < GitHub::TestCase
  include HydroTestHelpers
  include MemexHelpers
  include SubIssuesHelpers

  fixtures do
    @memex = create(:memex_project)
    @item = create(:memex_project_item, memex_project: @memex)
    @user = create(:user)
    @repo = create(:public_repository, owner: @user)
    @issue = create(:issue, user: @user, repository: @repo)
    @org_admin = create(:verified_user)
    @org = create(:organization, admin: @org_admin)
    @draft_item = build(:memex_project_item, memex_project: @memex, priority: 1)
    @draft_item.content = @draft_item.build_draft_issue(title: Faker::Lorem.unique.word)
    @draft_item.save!
  end

  context "#special_type_csv_column_value" do
    # This block intentionally uses `send` to unit test the private
    # `MemexProjectItem#special_column_type_csv_column_value` method. We have no
    # need outside of tests to make that method public, so while that's true
    # this technique allows to maintain a strong public interface while still
    # testing a reasonable complex sub-method. The public interface is also
    # tested separately at the integration test level.
    context "from non-denormalized data source" do
      test "returns assignee column data" do
        # This adds the repository's owner as the assignee, which in this case is @user.
        issue = create(:assigned_issue, repository: @repo)
        item = create(:memex_project_item, content: issue)

        assert_equal @user.login, item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::ASSIGNEES_COLUMN_NAME),
          require_prefilled_associations: false
        )
      end

      test "returns multiple assignees for an issue" do
        users = 3.times.map do
          create(:user).tap do |u|
            @org.add_member(u)
            @repo.add_member(u)
          end
        end

        issue = create(:issue, repository: @repo, assignees: [@user] + users)
        item = create(:memex_project_item, content: issue)
        assignees_column = item.memex_project.columns.find(&:assignees?)
        refute_nil assignees_column

        assert_equal ([@user.login] + users.map { |u| u.login }).sort.join(", "), item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::ASSIGNEES_COLUMN_NAME),
          require_prefilled_associations: false,
        )
      end

      test "returns assignee column data for a pull request" do
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
        assignees_column = item.memex_project.columns.find(&:assignees?)
        refute_nil assignees_column

        assert_equal @user.login, item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::ASSIGNEES_COLUMN_NAME),
          require_prefilled_associations: false,
        )
      end

      test "returns multiple assignees for a pull request" do
        users = 3.times.map do
          create(:user).tap do |u|
            @org.add_member(u)
            @repo.add_member(u)
          end
        end

        pull = create(
          :pull_request,
          :disable_disk_access,
          repository: @repo,
          user: @user
        ).tap do |p|
          p.issue.add_assignees([@user] + users)
          p.issue.save!
        end

        item = create(:memex_project_item, content: pull)

        assert_equal ([@user.login] + users.map { |u| u.login }).sort.join(", "), item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::ASSIGNEES_COLUMN_NAME),
          require_prefilled_associations: false,
        )
      end

      test "returns assignee column data for a draft issue" do
        @draft_item.content.update!(assignees: [@user])
        assignees_column = @draft_item.memex_project.columns.find(&:assignees?)
        refute_nil assignees_column

        assert_equal @user.login, @draft_item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::ASSIGNEES_COLUMN_NAME),
          require_prefilled_associations: false,
        )
      end

      test "returns label column data for a pull request" do
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

        assert_equal label.name, item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::LABELS_COLUMN_NAME),
          require_prefilled_associations: false
        )
      end

      test "returns milestone column data for an issue" do
        milestone = create(:milestone, repository: @repo)
        issue = create(:issue, repository: @repo, milestone: milestone)
        item = create(:memex_project_item, :with_denormalized_title, :with_denormalized_milestone, content: issue)

        assert_equal milestone.title, item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::MILESTONE_COLUMN_NAME),
          require_prefilled_associations: false
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
        item = create(:memex_project_item, :with_denormalized_title, :with_denormalized_milestone, content: pull)

        assert_equal milestone.title, item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::MILESTONE_COLUMN_NAME),
          require_prefilled_associations: false,
        )
      end

      test "returns repository column data for a pull request" do
        pull = create(:pull_request, :disable_disk_access, repository: @repo, user: @user)
        item = create(:memex_project_item, content: pull)

        assert_equal @repo.nwo, item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::REPOSITORY_COLUMN_NAME),
          require_prefilled_associations: false,
        )
      end

      test "returns repository column data for an issue" do
        issue = create(:issue, repository: @repo)
        item = create(:memex_project_item, content: issue)

        assert_equal @repo.nwo, item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::REPOSITORY_COLUMN_NAME),
          require_prefilled_associations: false,
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

          assert_equal parent_issue.url, item.send(
            :special_type_csv_column_value,
            MemexProjectColumn.default_column(MemexProjectColumn::PARENT_ISSUE_COLUMN_NAME),
            require_prefilled_associations: false,
          )
        end
      end

      test "returns nil column value for parent issue column for a pull request" do
        pull = create(:pull_request, :disable_disk_access, repository: @repo, user: @user)
        item = create(:memex_project_item, content: pull)

        assert_nil item.send(
          :special_type_csv_column_value,
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

        assert_equal "0%", item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::SUB_ISSUES_PROGRESS_COLUMN_NAME),
          require_prefilled_associations: false,
        )
      end

      test "returns nil column value for sub issue column for a pull request" do
        pull = create(:pull_request, :disable_disk_access, repository: @repo, user: @user)
        item = create(:memex_project_item, content: pull)

        assert_nil item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::SUB_ISSUES_PROGRESS_COLUMN_NAME),
          require_prefilled_associations: false,
        )
      end

      test "returns title column data for an issue" do
        title = "The Master Plan"
        issue = create(:issue, repository: @repo, title:)
        item = create(:memex_project_item, content: issue)

        assert_equal title, item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::TITLE_COLUMN_NAME),
          require_prefilled_associations: false,
        )
      end

      test "returns title column data for a pull request" do
        title = "The Antidote"
        pull = create(
          :pull_request,
          :disable_disk_access,
          repository: @repo,
          user: @user,
        ).tap do |p|
          p.issue.title = title
          p.issue.save!
        end
        item = create(:memex_project_item, content: pull)

        assert_equal title, item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::TITLE_COLUMN_NAME),
          require_prefilled_associations: false
        )
      end

      test "returns title column data for a draft issue" do
        draft_issue = create(:draft_issue, title: "Fix `#123`")
        item = create(:memex_project_item, content: draft_issue)

        assert_equal draft_issue.title, item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::TITLE_COLUMN_NAME),
          require_prefilled_associations: false,
        )
      end

      test "returns issue type column data for an issue" do
        issue_type = create(:issue_type, owner: @org, name: "test")
        repository = create(:repository, owner: @org)

        GitHub.flipper[:issue_types].enable(@org)

        issue = create(:issue, user: @org_admin, repository: repository, issue_type:)
        memex = create(:memex_project, owner: @org)
        item = create(:memex_project_item, content: issue, memex_project: memex)
        issue_type_column = memex.find_column_by_name_or_id(MemexProjectColumn::TYPE_COLUMN_NAME)
        refute_nil issue_type_column

        assert_equal issue_type.name, item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::TYPE_COLUMN_NAME),
          require_prefilled_associations: false
        )
      end

      test "returns linked pull request column data for an issue" do
        pull = create(
          :pull_request,
          :disable_disk_access,
          repository: @repo,
          user: @user,
        )
        issue = create(:issue, repository: @repo)
        create(:close_issue_reference, issue: issue, pull_request: pull)

        memex = create(:memex_project, owner: @org)
        item = create(:memex_project_item, content: issue, memex_project: memex)

        assert_equal pull.url, item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::LINKED_PULL_REQUESTS_COLUMN_NAME),
          require_prefilled_associations: false
        )
      end
    end

    context "from denormalized data source" do
      test "returns assignee column data for an issue" do
        # This adds the repository's owner as the assignee, which in this case is @user.
        issue = create(:assigned_issue, repository: @repo)
        item = create(:memex_project_item, content: issue)
        assignees_column = item.memex_project.columns.find(&:assignees?)
        refute_nil assignees_column

        prefilled_result = MemexProjectItemPrefiller.new(
          [item],
          columns: [assignees_column],
          read_denormalized_title: true,
          title_column: item.memex_project.columns.find(&:title?)
        ).prefill
        refute_nil prefilled_result

        assert_equal @user.login, item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::ASSIGNEES_COLUMN_NAME),
          require_prefilled_associations: false,
          prefilled_associations: prefilled_result
        )
      end

      test "returns multiple assignees for an issue" do
        users = 3.times.map do
          create(:user).tap do |u|
            @org.add_member(u)
            @repo.add_member(u)
          end
        end

        issue = create(:issue, repository: @repo, assignees: [@user] + users)
        item = create(:memex_project_item, content: issue)
        assignees_column = item.memex_project.columns.find(&:assignees?)
        refute_nil assignees_column

        prefilled_result = MemexProjectItemPrefiller.new(
          [item],
          columns: [assignees_column],
          read_denormalized_title: true,
          title_column: item.memex_project.columns.find(&:title?)
        ).prefill
        refute_nil prefilled_result

        assert_equal ([@user.login] + users.map { |u| u.login }).sort.join(", "), item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::ASSIGNEES_COLUMN_NAME),
          require_prefilled_associations: false,
          prefilled_associations: prefilled_result
        )
      end

      test "returns assignee column data for a pull request" do
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
        assignees_column = item.memex_project.columns.find(&:assignees?)
        refute_nil assignees_column

        prefilled_result = MemexProjectItemPrefiller.new(
          [item],
          columns: [assignees_column],
          read_denormalized_title: true,
          title_column: item.memex_project.columns.find(&:title?)
        ).prefill
        refute_nil prefilled_result

        assert_equal @user.login, item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::ASSIGNEES_COLUMN_NAME),
          require_prefilled_associations: false,
          prefilled_associations: prefilled_result
        )
      end

      test "returns multiple assignees for a pull request" do
        users = 3.times.map do
          create(:user).tap do |u|
            @org.add_member(u)
            @repo.add_member(u)
          end
        end

        pull = create(
          :pull_request,
          :disable_disk_access,
          repository: @repo,
          user: @user
        ).tap do |p|
          p.issue.add_assignees([@user] + users)
          p.issue.save!
        end

        item = create(:memex_project_item, content: pull)
        assignees_column = item.memex_project.columns.find(&:assignees?)
        refute_nil assignees_column

        prefilled_result = MemexProjectItemPrefiller.new(
          [item],
          columns: [assignees_column],
          read_denormalized_title: true,
          title_column: item.memex_project.columns.find(&:title?)
        ).prefill
        refute_nil prefilled_result

        assert_equal ([@user.login] + users.map { |u| u.login }).sort.join(", "), item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::ASSIGNEES_COLUMN_NAME),
          require_prefilled_associations: false,
          prefilled_associations: prefilled_result
        )
      end

      test "returns assignee column data for a draft issue" do
        @draft_item.content.update!(assignees: [@user])
        assignees_column = @draft_item.memex_project.columns.find(&:assignees?)
        refute_nil assignees_column

        prefilled_result = MemexProjectItemPrefiller.new(
          [@draft_item],
          columns: [assignees_column],
          read_denormalized_title: true,
          title_column: @draft_item.memex_project.columns.find(&:title?)
        ).prefill
        refute_nil prefilled_result

        assert_equal @user.login, @draft_item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::ASSIGNEES_COLUMN_NAME),
          require_prefilled_associations: false,
          prefilled_associations: prefilled_result
        )
      end

      test "returns reviewers for a pull request" do
        reviewer = create(:user).tap do |u|
          @org.add_member(u)
          @repo.add_member(u)
        end

        pull = create(:pull_request, :disable_disk_access, repository: @repo, head_user: @user)
        create(:review_request, pull_request: pull, reviewer:)
        item = create(:memex_project_item, content: pull)
        reviewers_column = item.memex_project.memex_project_columns.find(&:reviewers?)
        refute_nil reviewers_column

        prefilled_result = MemexProjectItemPrefiller.new(
          [item],
          columns: [reviewers_column],
          read_denormalized_title: true,
          title_column: item.memex_project.columns.find(&:title?)
        ).prefill
        refute_nil prefilled_result

        assert_equal reviewer.login, item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::REVIEWERS_COLUMN_NAME),
          require_prefilled_associations: false,
          prefilled_associations: prefilled_result
        )
      end

      test "returns label column data for an issue" do
        label_strs = %w(camel Zebra)
        zebra_label = create(:label, repository: @repo, name: label_strs.first)
        camel_label = create(:label, repository: @repo, name: label_strs.second)
        @repo.update!(labels: [zebra_label, camel_label])

        issue = create(:issue, repository: @repo).tap do |i|
          i.add_labels([zebra_label, camel_label])
          i.save!
        end
        item = create(:memex_project_item, :with_denormalized_title, content: issue)

        labels_column = item.memex_project.columns.find(&:labels?)
        refute_nil labels_column

        prefilled_result = MemexProjectItemPrefiller.new(
          [item],
          columns: [labels_column],
          read_denormalized_title: true,
          title_column: item.memex_project.columns.find(&:title?)
        ).prefill
        refute_nil prefilled_result

        labels_value = item.send(:special_type_csv_column_value, labels_column, prefilled_associations: prefilled_result)

        assert_equal label_strs.join(", "), labels_value
      end

      test "returns label column data for a pull request" do
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
        labels_column = item.memex_project.columns.find(&:labels?)
        refute_nil labels_column

        prefilled_result = MemexProjectItemPrefiller.new(
          [item],
          columns: [labels_column],
          read_denormalized_title: true,
          title_column: item.memex_project.columns.find(&:title?)
        ).prefill

        refute_nil prefilled_result
        labels_value = item.send(:special_type_csv_column_value, labels_column, prefilled_associations: prefilled_result)
        assert_equal label.name, labels_value
      end

      test "returns milestone column data for an issue" do
        milestone = create(:milestone, repository: @repo)
        issue = create(:issue, repository: @repo, milestone: milestone)
        item = create(:memex_project_item, :with_denormalized_title, :with_denormalized_milestone, content: issue)
        milestone_column = item.memex_project.columns.find(&:milestone?)
        refute_nil milestone_column

        prefilled_result = MemexProjectItemPrefiller.new(
          [item],
          columns: [milestone_column],
          read_denormalized_title: true,
          title_column: item.memex_project.columns.find(&:title?)
        ).prefill
        refute_nil prefilled_result

        assert_equal milestone.title, item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::MILESTONE_COLUMN_NAME),
          require_prefilled_associations: false,
          prefilled_associations: prefilled_result
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
        item = create(:memex_project_item, :with_denormalized_title, :with_denormalized_milestone, content: pull)
        milestone_column = item.memex_project.columns.find(&:milestone?)
        refute_nil milestone_column

        prefilled_result = MemexProjectItemPrefiller.new(
          [item],
          columns: [milestone_column],
          read_denormalized_title: true,
          title_column: item.memex_project.columns.find(&:title?)
        ).prefill
        refute_nil prefilled_result

        assert_equal milestone.title, item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::MILESTONE_COLUMN_NAME),
          require_prefilled_associations: false,
          prefilled_associations: prefilled_result
        )
      end

      test "returns repository column data for a pull request" do
        pull = create(:pull_request, :disable_disk_access, repository: @repo, user: @user)
        item = create(:memex_project_item, content: pull)
        repository_column = item.memex_project.columns.find(&:repository?)
        refute_nil repository_column

        prefilled_result = MemexProjectItemPrefiller.new(
          [item],
          columns: [repository_column],
          read_denormalized_title: true,
          title_column: item.memex_project.columns.find(&:title?)
        ).prefill
        refute_nil prefilled_result

        assert_equal @repo.nwo, item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::REPOSITORY_COLUMN_NAME),
          require_prefilled_associations: false,
          prefilled_associations: prefilled_result
        )
      end

      test "returns repository column data for an issue" do
        issue = create(:issue, repository: @repo)
        item = create(:memex_project_item, content: issue)
        repository_column = item.memex_project.columns.find(&:repository?)
        refute_nil repository_column

        prefilled_result = MemexProjectItemPrefiller.new(
          [item],
          columns: [repository_column],
          read_denormalized_title: true,
          title_column: item.memex_project.columns.find(&:title?)
        ).prefill
        refute_nil prefilled_result

        assert_equal @repo.nwo, item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::REPOSITORY_COLUMN_NAME),
          require_prefilled_associations: false,
          prefilled_associations: prefilled_result
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
          parent_issue_column = item.memex_project.columns.find(&:parent_issue?)
          refute_nil parent_issue_column

          prefilled_result = MemexProjectItemPrefiller.new(
            [item],
            columns: [parent_issue_column],
            read_denormalized_title: true,
            title_column: item.memex_project.columns.find(&:title?)
          ).prefill
          refute_nil prefilled_result

          assert_equal parent_issue.url, item.send(
            :special_type_csv_column_value,
            MemexProjectColumn.default_column(MemexProjectColumn::PARENT_ISSUE_COLUMN_NAME),
            require_prefilled_associations: false,
            prefilled_associations: prefilled_result
          )
        end
      end

      test "returns nil column value for parent issue column for a pull request" do
        pull = create(:pull_request, :disable_disk_access, repository: @repo, user: @user)
        item = create(:memex_project_item, content: pull)
        parent_issue_column = item.memex_project.columns.find(&:parent_issue?)
        refute_nil parent_issue_column

        prefilled_result = MemexProjectItemPrefiller.new(
          [item],
          columns: [parent_issue_column],
          read_denormalized_title: true,
          title_column: item.memex_project.columns.find(&:title?)
        ).prefill
        refute_nil prefilled_result

        assert_nil item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::PARENT_ISSUE_COLUMN_NAME),
          require_prefilled_associations: false,
          prefilled_associations: prefilled_result
        )
      end

      test "returns sub-issues progress data for an issue" do
        repository = create(:repository, owner: @org)
        memex = create(:memex_project, owner: @org)
        parent_issue = create(:issue, repository:, user: @org_admin)
        child_issue = create(:issue, repository:, user: @org_admin)
        parent_issue.add_sub_issue!(child_issue, @org_admin.id)

        item = create(:memex_project_item, memex_project: memex, content: parent_issue)
        sub_issue_column = item.memex_project.columns.find(&:sub_issues_progress?)
        refute_nil sub_issue_column

        prefilled_result = MemexProjectItemPrefiller.new(
          [item],
          columns: [sub_issue_column],
          read_denormalized_title: true,
          title_column: item.memex_project.columns.find(&:title?)
        ).prefill
        refute_nil prefilled_result

        assert_equal "0%", item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::SUB_ISSUES_PROGRESS_COLUMN_NAME),
          require_prefilled_associations: false,
          prefilled_associations: prefilled_result
        )
      end

      test "returns nil column value for sub issue column for a pull request" do
        pull = create(:pull_request, :disable_disk_access, repository: @repo, user: @user)
        item = create(:memex_project_item, content: pull)
        sub_issue_column = item.memex_project.columns.find(&:sub_issues_progress?)
        refute_nil sub_issue_column

        prefilled_result = MemexProjectItemPrefiller.new(
          [item],
          columns: [sub_issue_column],
          read_denormalized_title: true,
          title_column: item.memex_project.columns.find(&:title?)
        ).prefill
        refute_nil prefilled_result

        assert_nil item.send(
          :special_type_csv_column_value,
          MemexProjectColumn.default_column(MemexProjectColumn::SUB_ISSUES_PROGRESS_COLUMN_NAME),
          require_prefilled_associations: false,
          prefilled_associations: prefilled_result
        )
      end

      test "returns title column data for an issue" do
        title = "The Master Plan"
        issue = create(:issue, repository: @repo, title:)
        item = create(:memex_project_item, :with_denormalized_title, content: issue)
        title_column = item.memex_project.columns.find(&:title?)
        refute_nil title_column

        prefilled_result = MemexProjectItemPrefiller.new(
          [item],
          columns: [title_column],
          read_denormalized_title: true,
          title_column: item.memex_project.columns.find(&:title?)
        ).prefill
        refute_nil prefilled_result

        assert_equal title, item.send(
          :special_type_csv_column_value,
          title_column,
          require_prefilled_associations: false,
          prefilled_associations: prefilled_result
        )
      end

      test "returns title column data for a pull request" do
        title = "The Antidote"
        pull = create(
          :pull_request,
          :disable_disk_access,
          repository: @repo,
          user: @user,
        ).tap do |p|
          p.issue.title = title
          p.issue.save!
        end
        item = create(:memex_project_item, :with_denormalized_title, content: pull)
        title_column = item.memex_project.columns.find(&:title?)
        refute_nil title_column

        prefilled_result = MemexProjectItemPrefiller.new(
          [item],
          columns: [title_column],
          read_denormalized_title: true,
          title_column: item.memex_project.columns.find(&:title?)
        ).prefill
        refute_nil prefilled_result

        assert_equal title, item.send(
          :special_type_csv_column_value,
          title_column,
          prefilled_associations: prefilled_result
        )
      end

      test "returns title column data for a draft issue" do
        draft_issue = create(:draft_issue, title: "Fix `#123`")
        item = create(:memex_project_item, :with_denormalized_title, content: draft_issue)
        title_column = item.memex_project.columns.find(&:title?)
        refute_nil title_column

        prefilled_result = MemexProjectItemPrefiller.new(
          [item],
          columns: [title_column],
          read_denormalized_title: true,
          title_column: item.memex_project.columns.find(&:title?)
        ).prefill
        refute_nil prefilled_result

        assert_equal draft_issue.title, item.send(
          :special_type_csv_column_value,
          title_column,
          require_prefilled_associations: false,
          prefilled_associations: prefilled_result
        )
      end

      test "returns issue type column data for an issue" do
        issue_type = create(:issue_type, owner: @org, name: "test")
        repository = create(:repository, owner: @org)
        GitHub.flipper[:issue_types].enable(@org)
        issue = create(:issue, user: @org_admin, repository: repository, issue_type:)
        memex = create(:memex_project, owner: @org)
        item = create(:memex_project_item, content: issue, memex_project: memex)
        issue_type_column = memex.find_column_by_name_or_id(MemexProjectColumn::TYPE_COLUMN_NAME)
        refute_nil issue_type_column

        prefilled_result = MemexProjectItemPrefiller.new(
          [item],
          columns: [issue_type_column],
          read_denormalized_title: true,
          title_column: item.memex_project.columns.find(&:title?)
        ).prefill
        refute_nil prefilled_result

        assert_equal issue_type.name, item.send(
          :special_type_csv_column_value,
          issue_type_column,
          prefilled_associations: prefilled_result
        )
      end

      test "returns linked pull request column data for an issue" do
        pull = create(
          :pull_request,
          :disable_disk_access,
          repository: @repo,
          user: @user,
        )
        issue = create(:issue, repository: @repo)
        create(:close_issue_reference, issue: issue, pull_request: pull)

        memex = create(:memex_project, owner: @org)
        item = create(:memex_project_item, content: issue, memex_project: memex)
        linked_prs_column = memex.columns.find(&:linked_pull_requests?)
        refute_nil linked_prs_column

        prefilled_result = MemexProjectItemPrefiller.new(
          [item],
          columns: [linked_prs_column],
          read_denormalized_title: true,
          title_column: item.memex_project.columns.find(&:title?)
        ).prefill
        refute_nil prefilled_result

        assert_equal pull.url, item.send(
          :special_type_csv_column_value,
          linked_prs_column,
          prefilled_associations: prefilled_result
        )
      end
    end
  end
end
