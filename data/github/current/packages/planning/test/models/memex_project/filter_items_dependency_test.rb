# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectFilterItemsTest < GitHub::TestCase
  include MemexHelpers

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @org = create(:organization)
    @user = create(:verified_user, login: "jsnow").tap { |u| @org.add_member(u) }
    @collaborator = create(:verified_user, login: "collab").tap { |u| @org.add_member(u) }
    @rando = create(:user)
    @repo = create(:repository, owner: @org)
    @user_repo = create(:repository, owner: @user)
    @issue = create(:issue, repository: @repo, user: @user)
    @user_issue = create(:issue, repository: @user_repo, user: @user)
    @issue_for_archiving = create(:issue, title: "issue for archiving", repository: @repo, user: @user)
    @user_issue_for_archiving = create(:issue, title: "issue for archiving", repository: @user_repo, user: @user)
    @pull = create(:pull_request, :disable_disk_access, repository: @repo, user: @user)
    @user_pull = create(:pull_request, :disable_disk_access, repository: @user_repo, user: @user)

    @memex = create_memex_with_items_and_custom_columns
    @user_memex = create_user_memex_with_items_and_custom_columns

    @iteration_column = create(:iteration_memex_column, memex_project: @memex)
    @item = create(:memex_project_item, memex_project: @memex)
    @value = create(
      :iteration_memex_project_column_value,
      item: @item,
      column: @iteration_column,
      value: @iteration_column.settings_iterations.first["id"]
    )

    @user_iteration_column = create(:iteration_memex_column, memex_project: @user_memex)
    @user_item = create(:memex_project_item, memex_project: @user_memex)
    @user_value = create(
      :iteration_memex_project_column_value,
      item: @user_item,
      column: @user_iteration_column,
      value: @user_iteration_column.settings_iterations.first["id"]
    )

    @apps_with_read = Api::TestCase::AppsAuthzMatrix.new(target: @org, permissions: { "organization_projects" => :read })

    @status_column = @memex.status_column

    in_progress_option_id = @status_column.settings_options.find { |o| o["name"] == "In Progress" }["id"]
    in_progress_issue = create(:issue, repository: @repo, user: @user)
    @in_progress_item = create(:memex_project_item, memex_project: @memex, creator: @user)
    columns = [{ column: @status_column, value: in_progress_option_id }]
    MemexProjectItemSetColumnsJob.perform_now(@in_progress_item.id, columns, @user.id)

    done_option_id = @status_column.settings_options.find { |o| o["name"] == "Done" }["id"]
    done_issue = create(:issue, repository: @repo, user: @user)
    @done_item = create(:memex_project_item, memex_project: @memex, creator: @user)
    columns = [{ column: @status_column, value: done_option_id }]
    MemexProjectItemSetColumnsJob.perform_now(@done_item.id, columns, @user.id)

    @assigned_issue = create(:assigned_issue, repository: @repo, assignee: @user)
    @assigned_item = use_project_next_platform_type(create(:memex_project_item, memex_project: @memex, content: @assigned_issue))

    @memex_items = @memex.prioritized_scope(:memex_project_items).not_archived
  end

  setup do
    @org.enable_organization_projects(actor: @user)
  end

  context "#filter_items" do
    # Ensure the underlying implementation does not allow user-controlled input to be affected by
    # regular expression syntax (see: https://github.com/github/mobile-api/issues/256)
    test "when a column name contains regular expression special characters" do
      date_column = create(
        :memex_project_column,
        user_defined: true,
        data_type: :date,
        memex_project: @memex,
        name: "date)"
      )

      @item.set_column_value(date_column, "02-02-2099", @user)
      filtered = @memex.reload.filter_items(memex_items: @memex_items, filter: "#{date_column.name_slug}:01-01-2021..")
      assert_includes filtered, @item
    end

    test "filters items with single qualifier" do
      filtered_in_progress = @memex.filter_items(memex_items: @memex_items, filter: "status:\"In Progress\"")
      assert_same_elements [@in_progress_item], filtered_in_progress

      filtered_done = @memex.filter_items(memex_items: @memex_items, filter: "status:\"Done\"")
      assert_same_elements [@done_item], filtered_done

      filtered_absence = @memex.filter_items(memex_items: @memex_items, filter: "no:status")
      assert_includes filtered_absence, @item
      refute_includes filtered_absence, @in_progress_item
      refute_includes filtered_absence, @done_item
    end

    test "filters items with multiple qualifiers" do
      filtered = @memex.filter_items(memex_items: @memex_items, filter: "status:\"In Progress\",done")

      assert_same_elements [@in_progress_item, @done_item], filtered
      refute_includes filtered, @item
    end

    test "filters items with multiple qualifiers and multiple columns" do
      filtered_absence = @memex.filter_items(memex_items: @memex_items, filter: "status:\"In Progress\",done no:label")
      assert_includes filtered_absence, @in_progress_item
      assert_includes filtered_absence, @done_item

      filtered_label = @memex.filter_items(memex_items: @memex_items, filter: "status:\"In Progress\",done label:bug")
      refute_includes filtered_label, @in_progress_item
      refute_includes filtered_label, @done_item
    end

    test "filters items with absence" do
      filtered = @memex.filter_items(memex_items: @memex_items, filter: "no:status")
      refute_includes filtered, @in_progress_item
      refute_includes filtered, @done_item
      assert_includes filtered, @item
    end

    test "filters items with negation" do
      filtered = @memex.filter_items(memex_items: @memex_items, filter: "-no:status")
      assert_includes filtered, @in_progress_item
      assert_includes filtered, @done_item
      refute_includes filtered, @item
    end

    test "filters items with negation includes nil values" do
      filtered = @memex.filter_items(memex_items: @memex_items, filter: "-label:bug")
      assert_includes filtered, @in_progress_item
      assert_includes filtered, @done_item
    end

    context "with a date column" do
      context "with equality operator" do
        test "filters items" do
          date_column = create(
            :memex_project_column,
            user_defined: true,
            data_type: :date,
            memex_project: @memex,
            name: "date"
          )

          @item.set_column_value(date_column, "01-01-2021", @user)
          filtered = @memex.reload.filter_items(memex_items: @memex_items, filter: "#{date_column.name_slug}:\"01-01-2021\"")
          assert_includes filtered, @item
        end
      end

      context "with greater than operator" do
        test "returns items when item date is greater" do
          date_column = create(
            :memex_project_column,
            user_defined: true,
            data_type: :date,
            memex_project: @memex,
            name: "date"
          )

          @item.set_column_value(date_column, "01-01-2021", @user)
          filtered = @memex.reload.filter_items(memex_items: @memex_items, filter: "#{date_column.name_slug}:>\"12-12-2020\"")
          assert_includes filtered, @item
        end
      end

      context "@today" do
        test "returns items when item date is greater than @today" do
          date_column = create(
            :memex_project_column,
            user_defined: true,
            data_type: :date,
            memex_project: @memex,
            name: "date"
          )

          @item.set_column_value(date_column, (Date.today + 1).strftime("%Y-%m-%d"), @user)
          filtered = @memex.reload.filter_items(memex_items: @memex_items, filter: "#{date_column.name_slug}:>@today")
          assert_includes filtered, @item
        end

        test "returns items when item date is greater than or equal to @today" do
          date_column = create(
            :memex_project_column,
            user_defined: true,
            data_type: :date,
            memex_project: @memex,
            name: "date"
          )

          @item.set_column_value(date_column, (Date.today + 1).strftime("%Y-%m-%d"), @user)
          filtered = @memex.reload.filter_items(memex_items: @memex_items, filter: "#{date_column.name_slug}:>=@today")
          assert_includes filtered, @item

          @item.set_column_value(date_column, (Date.today).strftime("%Y-%m-%d"), @user)
          filtered = @memex.reload.filter_items(memex_items: @memex_items, filter: "#{date_column.name_slug}:>=@today")
          assert_includes filtered, @item
        end


        test "returns items when item date is less than @today" do
          date_column = create(
            :memex_project_column,
            user_defined: true,
            data_type: :date,
            memex_project: @memex,
            name: "date"
          )

          @item.set_column_value(date_column, (Date.today - 1).strftime("%Y-%m-%d"), @user)
          filtered = @memex.reload.filter_items(memex_items: @memex_items, filter: "#{date_column.name_slug}:<@today")
          assert_includes filtered, @item
        end

        test "returns items when item date is less than or equal to @today" do
          date_column = create(
            :memex_project_column,
            user_defined: true,
            data_type: :date,
            memex_project: @memex,
            name: "date"
          )

          @item.set_column_value(date_column, (Date.today - 1).strftime("%Y-%m-%d"), @user)
          filtered = @memex.reload.filter_items(memex_items: @memex_items, filter: "#{date_column.name_slug}:<=@today")
          assert_includes filtered, @item

          @item.set_column_value(date_column, (Date.today).strftime("%Y-%m-%d"), @user)
          filtered = @memex.reload.filter_items(memex_items: @memex_items, filter: "#{date_column.name_slug}:<=@today")
          assert_includes filtered, @item
        end

        test "honors user timezone" do
          date_column = create(
            :memex_project_column,
            user_defined: true,
            data_type: :date,
            memex_project: @memex,
            name: "date"
          )
          @item.set_column_value(date_column, "2023-01-01", @user)

          # Go to 22:00 UTC on 2023-01-01, which in America/Chicago will be the same date as the column value, but
          # will be the next day in Asia/Tokyo.  This ensures that the filter is honoring the user's timezone.
          travel_to Time.utc(2023, 1, 1, 22, 0, 0) do
            user1 = create(:user)
            user1.update(time_zone_name: "America/Chicago")
            filtered1 = @memex.reload.filter_items(memex_items: @memex_items, filter: "#{date_column.name_slug}:>=@today", viewer: user1)
            assert_includes filtered1, @item

            user2 = create(:user)
            user2.update(time_zone_name: "Asia/Tokyo")
            filtered2 = @memex.reload.filter_items(memex_items: @memex_items, filter: "#{date_column.name_slug}:>=@today", viewer: user2)
            refute_includes filtered2, @item
          end
        end
      end

      context "with greater than or equal to operator" do
        test "returns items when item date is greater" do
          date_column = create(
            :memex_project_column,
            user_defined: true,
            data_type: :date,
            memex_project: @memex,
            name: "date"
          )

          @item.set_column_value(date_column, "01-01-2021", @user)
          filtered = @memex.reload.filter_items(memex_items: @memex_items, filter: "#{date_column.name_slug}:>=\"12-12-2020\"")
          assert_includes filtered, @item
        end

        test "returns items when item date is equal" do
          date_column = create(
            :memex_project_column,
            user_defined: true,
            data_type: :date,
            memex_project: @memex,
            name: "date"
          )

          @item.set_column_value(date_column, "12-12-2020", @user)
          filtered = @memex.reload.filter_items(memex_items: @memex_items, filter: "#{date_column.name_slug}:>=\"12-12-2020\"")
          assert_includes filtered, @item
        end
      end

      context "with less than operator" do
        test "returns items when item date is before" do
          date_column = create(
            :memex_project_column,
            user_defined: true,
            data_type: :date,
            memex_project: @memex,
            name: "date"
          )

          @item.set_column_value(date_column, "01-01-2021", @user)
          filtered = @memex.reload.filter_items(memex_items: @memex_items, filter: "#{date_column.name_slug}:<\"02-02-2021\"")
          assert_includes filtered, @item
        end
      end

      context "with less than or equal to operator" do
        test "returns items when item date is before" do
          date_column = create(
            :memex_project_column,
            user_defined: true,
            data_type: :date,
            memex_project: @memex,
            name: "date"
          )

          @item.set_column_value(date_column, "01-01-2021", @user)
          filtered = @memex.reload.filter_items(memex_items: @memex_items, filter: "#{date_column.name_slug}:<=\"02-02-2021\"")
          assert_includes filtered, @item
        end

        test "returns items when item date is equal" do
          date_column = create(
            :memex_project_column,
            user_defined: true,
            data_type: :date,
            memex_project: @memex,
            name: "date"
          )

          @item.set_column_value(date_column, "01-01-2021", @user)
          filtered = @memex.reload.filter_items(memex_items: @memex_items, filter: "#{date_column.name_slug}:<=\"01-01-2021\"")
          assert_includes filtered, @item
        end
      end

      context "with range operator" do
        context "when only the start date is present" do
          test "returns items when item date is greater than start date" do
            date_column = create(
              :memex_project_column,
              user_defined: true,
              data_type: :date,
              memex_project: @memex,
              name: "date"
            )

            @item.set_column_value(date_column, "02-02-2099", @user)
            filtered = @memex.reload.filter_items(memex_items: @memex_items, filter: "#{date_column.name_slug}:01-01-2021..")
            assert_includes filtered, @item
          end

          test "returns items when item date is equal to start date" do
            date_column = create(
              :memex_project_column,
              user_defined: true,
              data_type: :date,
              memex_project: @memex,
              name: "date"
            )

            @item.set_column_value(date_column, "01-01-2021", @user)
            filtered = @memex.reload.filter_items(memex_items: @memex_items, filter: "#{date_column.name_slug}:01-01-2021..")
            assert_includes filtered, @item
          end
        end

        context "when only the end date is present" do
          test "returns items when item date is less than end date" do
            date_column = create(
              :memex_project_column,
              user_defined: true,
              data_type: :date,
              memex_project: @memex,
              name: "date"
            )

            @item.set_column_value(date_column, "02-02-2055", @user)
            filtered = @memex.reload.filter_items(memex_items: @memex_items, filter: "#{date_column.name_slug}:..01-01-2099")
            assert_includes filtered, @item
          end

          test "returns items when item date is equal to end date" do
            date_column = create(
              :memex_project_column,
              user_defined: true,
              data_type: :date,
              memex_project: @memex,
              name: "date"
            )

            @item.set_column_value(date_column, "01-01-2021", @user)
            filtered = @memex.reload.filter_items(memex_items: @memex_items, filter: "#{date_column.name_slug}:..01-01-2021")
            assert_includes filtered, @item
          end
        end

        context "when start and end dates are both omitted" do
          test "returns items" do
            date_column = create(
              :memex_project_column,
              user_defined: true,
              data_type: :date,
              memex_project: @memex,
              name: "date"
            )

            @item.set_column_value(date_column, "02-02-2055", @user)
            filtered = @memex.reload.filter_items(memex_items: @memex_items, filter: "#{date_column.name_slug}:..")
            assert_includes filtered, @item
          end
        end

        context "when both start and end dates are present" do
          test "returns items when item date is between" do
            date_column = create(
              :memex_project_column,
              user_defined: true,
              data_type: :date,
              memex_project: @memex,
              name: "date"
            )

            @item.set_column_value(date_column, "02-02-2021", @user)
            filtered = @memex.reload.filter_items(memex_items: @memex_items, filter: "#{date_column.name_slug}:01-01-2021..03-03-2021")
            assert_includes filtered, @item
          end

          # Ensure that the filter is inclusive of the start date
          test "returns items when item date is same as the from date" do
            date_column = create(
              :memex_project_column,
              user_defined: true,
              data_type: :date,
              memex_project: @memex,
              name: "date"
            )

            @item.set_column_value(date_column, "01-01-2021", @user)
            filtered = @memex.reload.filter_items(memex_items: @memex_items, filter: "#{date_column.name_slug}:01-01-2021..03-03-2021")
            assert_includes filtered, @item
          end

          # Ensure that the filter is inclusive of the end date
          test "returns items when item date is same as the to date" do
            date_column = create(
              :memex_project_column,
              user_defined: true,
              data_type: :date,
              memex_project: @memex,
              name: "date"
            )

            @item.set_column_value(date_column, "03-03-2021", @user)
            filtered = @memex.reload.filter_items(memex_items: @memex_items, filter: "#{date_column.name_slug}:01-01-2021..03-03-2021")
            assert_includes filtered, @item
          end
        end
      end
    end

    # There are alot of is filtering combinations that need to be tested and adding them
    # all here would explode the size of this file.  Instead, lets do finer-grained/matrix testing
    # within the IsKeyWordfilterTest class and keep this file limited to some integration and smoke tests.
    context "is keyword filtering" do
      test "matches issue keyword" do
        # note that is:issue will also return draft issues so if draft issue items are added to fixtures
        # then this would need to be updated to include DraftIssue content_types.
        filtered_items       = @memex.filter_items(memex_items: @memex_items, filter: "is:issue")
        actual_content_types = filtered_items.map(&:content_type).uniq

        assert_same_elements ["Issue"], actual_content_types
      end

      test "matches pr keyword" do
        filtered_items       = @memex.filter_items(memex_items: @memex_items, filter: "is:pr")
        actual_content_types = filtered_items.map(&:content_type).uniq

        assert_same_elements ["PullRequest"], actual_content_types
      end
    end

    test "filters items with iteration values" do
      title = @iteration_column.settings_iterations.first["title"]

      filtered = @memex.filter_items(memex_items: @memex_items, filter: "#{@iteration_column.name_slug}:\"#{title}\"")
      assert_includes filtered, @item
    end

    test "filters items with multiselect column values" do
      create(:review_request, reviewer_id: @collaborator.id, pull_request: @pull)

      filtered = @memex.filter_items(memex_items: @memex_items, filter: "reviewers:collab")
      assert_equal 1, filtered.size
      assert_equal @pull, filtered.first.content
    end

    test "returns all items when no filter is provided" do
      filtered = @memex.filter_items(memex_items: @memex_items)
      assert_same_elements @memex.memex_project_items.not_archived, filtered
    end

    test "returns no items when conflicting filters are provided" do
      filtered = @memex.filter_items(memex_items: @memex_items, filter: "status:\"In Progress\" no:status")
      assert_empty filtered
    end

    test "returns no items when no items match the filter" do
      filtered = @memex.filter_items(memex_items: @memex_items, filter: "status:foobar123")
      assert_empty filtered
    end

    test "returns items matching issue type in the filter" do
      enable_feature_flag(:issue_types)
      memex = create(:memex_project, owner: @org)
      issue_type_column = memex.find_column_by_name_or_id(MemexProjectColumn::TYPE_COLUMN_NAME)
      issue_type = create(:issue_type, owner: @org, name: "test")
      repository = create(:repository, owner: @org)
      issue = create(:issue, repository: repository, issue_type: issue_type)
      item = create(:memex_project_item, memex_project: memex, content: issue)

      filtered = memex.reload.filter_items(memex_items: [item], filter: "type:test")
      refute_nil issue_type_column, "Expected Type column to be present"
      assert_equal [item], filtered
    end

    test "returns no items when no items match issue type filter" do
      issue_type_column = @memex.find_column_by_name_or_id(MemexProjectColumn::TYPE_COLUMN_NAME)
      filtered = @memex.reload.filter_items(memex_items: @memex_items, filter: "type:foobar123")
      assert_nil @memex.owner.issue_types.find_by(name: "foobar123")
      refute_nil issue_type_column, "Expected Type column to be present"
      assert_empty filtered
    end

    test "returns no items when an invalid column name is passed in" do
      filtered = @memex.filter_items(memex_items: @memex_items, filter: "reviewers:foo fake_column:bar")
      assert_empty filtered
    end

    test "filters on custom columns" do
      custom_column = create(:memex_project_column, memex_project: @memex, name: "custom")
      assert_empty @memex.reload.filter_items(memex_items: @memex_items, filter: "custom:value")

      columns = [{ column: custom_column, value: "value" }]
      MemexProjectItemSetColumnsJob.perform_now(@item.id, columns, @user.id)

      filtered = @memex.filter_items(memex_items: @memex_items, filter: "custom:value")
      assert_includes filtered, @item
    end

    test "filters by absence of columns in REPLACEMENT_SLUGS" do
      assert_same_elements [@assigned_item], @memex.filter_items(memex_items: @memex_items, filter: "-no:assignee")

      refute_empty @memex.filter_items(memex_items: @memex_items, filter: "no:assignee")
    end

    test "returns assigned items" do
      filtered = @memex.filter_items(memex_items: @memex_items, filter: "assignee:@me", viewer: @user)
      assert_same_elements [@assigned_item], filtered
    end

    test "does not return assigned items if viewer does not match" do
      filtered = @memex.filter_items(memex_items: @memex_items, filter: "assignee:@me")
      assert_empty filtered

      filtered = @memex.filter_items(memex_items: @memex_items, filter: "assignee:@me", viewer: @collaborator)
      assert_empty filtered
    end

    test "prefills with visible columns" do
      args = {
        columns: [@iteration_column, @status_column],
        read_denormalized_title: true,
        title_column: @memex.memex_project_columns.find(&:title?)
      }

      prefiller = MemexProjectItemPrefiller.new(@memex_items, **args)

      MemexProjectItemPrefiller.expects(:new).with(@memex_items, **args).returns(prefiller)

      @memex.filter_items(memex_items: @memex_items, filter: "no:status", visible_fields: [@iteration_column.id])
    end
  end

  def create_memex_with_items_and_custom_columns
    memex = create_memex_with_associations_using_project_next(
      owner: @org,
      creator: @user,
      title: "Test memex"
    )

    memex.update!(description: "Amazing!")

    item = memex.build_item(
      creator: @user,
      issue_or_pull: @issue
    )
    item.save!

    item = memex.build_item(
      creator: @user,
      issue_or_pull: @pull
    )

    item.save!

    archived_item = memex.build_item(
      creator: @user,
      issue_or_pull: @issue_for_archiving
    )

    archived_item.save!
    archived_item.archive!

    column = create(
      :memex_project_column,
      user_defined: true,
      data_type: :text,
      memex_project: memex,
      name: "custom column"
    )
    use_project_next_platform_type(column)

    value = create(
      :memex_project_column_value,
      value: "foo",
      memex_project_column: column,
      memex_project_item: item
    )

    memex
  end

  def create_user_memex_with_items_and_custom_columns
    memex = create_memex_with_associations_using_project_next(
      owner: @user,
      creator: @user,
      title: "Test memex"
    )

    memex.update!(description: "Sensational!")

    item = memex.build_item(
      creator: @user,
      issue_or_pull: @user_issue
    )

    item.save!

    item = memex.build_item(
      creator: @user,
      issue_or_pull: @user_pull
    )

    item.save!

    archived_item = memex.build_item(
      creator: @user,
      issue_or_pull: @user_issue_for_archiving
    )

    archived_item.save!
    archived_item.archive!

    column = create(
      :memex_project_column,
      user_defined: true,
      data_type: :text,
      memex_project: memex,
      name: "custom column"
    )
    use_project_next_platform_type(column)

    value = create(
      :memex_project_column_value,
      value: "foo",
      memex_project_column: column,
      memex_project_item: item
    )

    memex
  end
end
