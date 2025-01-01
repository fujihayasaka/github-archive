# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesMemexProjectItemQueryRedactorTest < GitHub::TestCase
  include MemexHelpers
  include DogstatsTestHelpers

  MISSING_VALUE_GROUP_KEY = MemexProjectColumn::Interface::Groupable::MISSING_VALUE_GROUP_KEY

  fixtures do
    @user = create(:verified_user, login: "joe-schmo")
    @org_admin = create(:verified_user)
    @org = create(:organization, admin: @org_admin)
    @memex = create(:memex_project, owner: @org, creator: @user)
    @public_repo = create(:repository, owner: @org, name: "public_org_repo")

    # Site admin viewer
    @site_admin_member = create(:staff_admin_user)
    @org.add_member(@site_admin_member)

    # Example users
    @spammy_user = create(:verified_user, login: "spammy-user", spammy: true)
    @spammy_user2 = create(:verified_user, login: "spammy-user2", spammy: true)
    @non_spammy_user = create(:verified_user, login: "non-spammy-user")
    @ten_non_spammy_users = 10.times.map { create(:verified_user) }

    # Use a text "Comments" column to help identify spammy items in slices
    @comments_column = create(
      :memex_project_column,
      name: "Comments",
      data_type: :text,
      user_defined: true,
      memex_project: @memex
    )

    # Five non-spammy issue items created by and assigned to the first five non-spammy users
    @non_spammy_items = 5.times.map do |n|
      rando_user = @ten_non_spammy_users[n % 10]
      issue = create(:issue, title: "non-spammy issue #{n}", repository: @public_repo, assignees: [rando_user], user: rando_user)
      item = create(:memex_project_item, memex_project: @memex, creator: rando_user, content: issue).tap { |i| i.set_column_value(@comments_column, "Legit issue item", rando_user) }
    end

    # Example non-spammy draft issue
    @non_spammy_draft_item = create(:memex_project_item, memex_project: @memex, creator: @non_spammy_user, content: create(:draft_issue))

    # Example spammy items
    @spammy_item = create(:memex_project_item, memex_project: @memex, creator: @spammy_user)
    @spammy_item.set_column_value(@comments_column, "Spammy item", @user)
    @spammy_draft_item = create(:memex_project_item, memex_project: @memex, creator: @spammy_user2, content: create(:draft_issue))
    @spammy_draft_item.set_column_value(@comments_column, "Spammy draft item", @user)
    # Example item with spammy issue
    @spammy_issue = create(:issue, title: "spammy issue", repository: @public_repo, user: @spammy_user)
    @item_with_spammy_issue = create(:memex_project_item, memex_project: @memex, creator: @non_spammy_user, content: @spammy_issue)
    @item_with_spammy_issue.set_column_value(@comments_column, "Spammy issue item", @user)
    # Example item with spammy pull request
    @spammy_pull_request = create(:pull_request, :disable_disk_access, repository: @public_repo, head_ref: "ref-#{SecureRandom.hex(6)}", user: @spammy_user2)
    @item_with_spammy_pull_request = create(:memex_project_item, memex_project: @memex, creator: @non_spammy_user, content: @spammy_pull_request)
    @item_with_spammy_pull_request.set_column_value(@comments_column, "Spammy pull request item", @user)
  end

  setup do
    GitHub.flipper[:memex_mwl_spam_redaction].enable
    setup_search
  end

  teardown_once do
    teardown_search
  end

  context "repository auth redactions" do
    test "Redacts slices and items, slicing by Assignees, with or without slice_value", es_8_only: true do
      private_repo_admin = create(:user)
      private_repo = create(:private_repository, owner: private_repo_admin)

      user_ren = create(:verified_user, login: "ren")
      user_stimpy = create(:verified_user, login: "stimpy")
      user_george = create(:verified_user, login: "george")
      user_muddy = create(:verified_user, login: "muddy")
      private_repo.add_member(user_george)
      private_repo.add_member(user_muddy)
      @public_repo.add_member(user_ren)
      @public_repo.add_member(user_stimpy)
      @public_repo.add_member(user_george)
      @public_repo.add_member(user_muddy)
      assignee_col_id = @memex.columns.find(&:assignees?)&.id

      items = Array[create(:memex_project_item, content: create(:issue, repository: @public_repo), memex_project: @memex)] #0
      items << create(:memex_project_item, content: create(:issue, assignees: [user_stimpy], repository: @public_repo), memex_project: @memex) #1
      items << create(:memex_project_item, content: create(:issue, assignees: [user_george, user_muddy], repository: private_repo), memex_project: @memex) #2 - redacted private_repo
      items << create(:memex_project_item, content: create(:issue, assignees: [user_ren], repository: @public_repo), memex_project: @memex) #3
      items << create(:memex_project_item, content: create(:issue, assignees: [user_ren], repository: @public_repo), memex_project: @memex) #4
      items << create(:memex_project_item, content: create(:issue, assignees: [user_ren, user_stimpy], repository: @public_repo), memex_project: @memex) #5
      items << create(:memex_project_item, content: create(:issue, assignees: [user_george, user_stimpy, user_ren], repository: @public_repo), memex_project: @memex) #6

      populate_elasticsearch_index!(items)

      # 4 non-zero Assignee values in the project view filter, excluding "muddy" who is only in the redacted private_repo item.
      # Slice values and counts do not change regardless of the slice_value applied to the query.
      # Counts do not include contributions from redacted items (hence only 1 for george)
      expected_slice_values = [user_george.login, user_ren.login, user_stimpy.login, MISSING_VALUE_GROUP_KEY]
      expected_sorted_slice_counts = [1, 4, 3, 1]

      # 1) Slice on Assignees, without a slice_value
      response = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
      Search::Queries::MemexProjectItemQuery.stub_const(:MAX_PAGE_SIZE, 10) do
        query = Search::Queries::MemexProjectItemQuery.new(
          project: @memex,
          viewer: @user,
          slice_by: assignee_col_id,
        )
        response = query.execute
      end

      # Assert we have the expected redacted slice values and counts
      assert_equal expected_slice_values, response&.slices&.map { |s| s["slice_value"] }
      assert_equal expected_sorted_slice_counts, response&.slices&.map { |s| s["total_count"] }

      # Assert we have the expected items (omitting the redacted item)
      assert_equal items.values_at(0, 1, 3, 4, 5, 6).map(&:id), response&.results&.map { |r| r["_id"].to_i }

      # 2) Slice on Assignees, with a slice_value "george"
      response = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
      Search::Queries::MemexProjectItemQuery.stub_const(:MAX_PAGE_SIZE, 10) do
        query = Search::Queries::MemexProjectItemQuery.new(
          project: @memex,
          viewer: @user,
          slice_by: assignee_col_id,
          slice_value: user_george.login
        )
        response = query.execute
      end

      # Assert we have the same expected redacted slice values and counts
      assert_equal expected_slice_values, response&.slices&.map { |s| s["slice_value"] }
      assert_equal expected_sorted_slice_counts, response&.slices&.map { |s| s["total_count"] }

      # Assert we have the expected items (omitting the redacted item).  Just the one for "george"
      assert_equal items.values_at(6).map(&:id), response&.results&.map { |r| r["_id"].to_i }
    end

    test "returns only draft items if the user is not authorized to access any repositories", es_8_only: true do
      private_repo = create(:private_repository)

      items = Array[create(:memex_project_item, content: create(:issue, repository: private_repo), memex_project: @memex)] #0 redacted private_repo
      items << create(:memex_project_item, content: create(:draft_issue), memex_project: @memex) #1 - draft issue 1
      items << create(:memex_project_item, content: create(:draft_issue), memex_project: @memex) #2 - draft issue 2

      populate_elasticsearch_index!(items)

      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
      )
      response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)

      # Two Elasticsearch query executions were made since the user cannot access private_repo
      assert_equal 2, GitHub.dogstats.increments("search.query.total").length

      # Assert we have the expected draft items, omitting the redacted private_repo item
      assert_equal items.values_at(1, 2).map(&:id), response.results&.map { |r| r["_id"].to_i }
    end

    test "correctly redacts items via programmatic access by a GitHub App", es_8_only: true do
      private_repo1 = create(:private_repository)
      private_repo2 = create(:private_repository)

      items = T.let([], T::Array[MemexProjectItem])
      items << create(:memex_project_item, content: create(:issue, repository: private_repo1), memex_project: @memex) #0 - private_repo1
      items << create(:memex_project_item, content: create(:issue, repository: private_repo1), memex_project: @memex) #1 - private_repo1
      items << create(:memex_project_item, content: create(:issue, repository: private_repo2), memex_project: @memex) #2 - redacted private_repo2
      items << create(:memex_project_item, content: create(:draft_issue), memex_project: @memex) #3 - draft issue 1
      items << create(:memex_project_item, content: create(:draft_issue), memex_project: @memex) #4 - draft issue 2

      populate_elasticsearch_index!(items)

      # Create an app with read access to private_repo1
      integration = create(:integration, default_permissions: { "contents" => :read })
      installation = make_integration_installation(integration: integration, repository: private_repo1)

      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: installation.bot,
      )
      response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)

      # Two Elasticsearch query executions were made since the app cannot access private_repo2
      assert_equal 2, GitHub.dogstats.increments("search.query.total").length

      # Assert we have the expected private_repo1 and draft items, omitting the redacted private_repo2 item
      assert_equal items.values_at(0, 1, 3, 4).map(&:id), response.results&.map { |r| r["_id"].to_i }
    end
  end

  context "project_item_owner_ids with redactions" do
    test "returns expected item owner ids, item counts, and slice counts, with or without redactions, exercising global aggregations", es_8_only: true do
      private_repo_admin = create(:user)
      private_repo = create(:private_repository, owner: private_repo_admin)
      another_org_repo = create(:private_repository, :org_owned)
      public_repo2 = create(:public_repository)

      user_ren = create(:verified_user, login: "ren")
      user_stimpy = create(:verified_user, login: "stimpy")
      user_drafter = create(:verified_user, login: "drafter")
      private_repo.add_member(user_stimpy)
      another_org_repo.add_member(user_stimpy)
      public_repo2.add_member(user_ren)
      @public_repo.add_member(user_ren)
      @public_repo.add_member(user_stimpy)

      assignee_col_id = @memex.columns.find(&:assignees?)&.id

      items = Array[create(:memex_project_item, content: create(:issue, repository: @public_repo), memex_project: @memex)] #0
      items << create(:memex_project_item, content: create(:issue, assignees: [user_stimpy], repository: another_org_repo), memex_project: @memex) #1 - redacted another_org_repo
      items << create(:memex_project_item, content: create(:issue, assignees: [user_stimpy], repository: private_repo), memex_project: @memex) #2 - redacted private_repo
      items << create(:memex_project_item, content: create(:issue, assignees: [user_ren], repository: @public_repo), memex_project: @memex) #3
      items << create(:memex_project_item, content: create(:issue, assignees: [user_ren], repository: @public_repo), memex_project: @memex) #4
      items << create(:memex_project_item, content: create(:issue, assignees: [user_ren, user_stimpy], repository: @public_repo), memex_project: @memex) #5
      items << create(:memex_project_item, content: create(:issue, assignees: [user_stimpy], repository: @public_repo), memex_project: @memex) #6
      items << create(:memex_project_item, content: create(:draft_issue).tap { |d| d.update!(assignees: [user_drafter]) }, memex_project: @memex) #7 - draft issue
      items << create(:memex_project_item, content: create(:issue, assignees: [user_ren], repository: public_repo2), memex_project: @memex) #8 - public_repo

      populate_elasticsearch_index!(items)

      # Regardless of redactions or the query filtering, we always return the same array of project item owner ids.
      # We also always query the MySQL Repository table only once for redactions and owner ids.
      expected_project_item_owner_ids = [@public_repo, private_repo, another_org_repo, public_repo2].map { |r| r.owner.id }
      query_count = 0

      # Loop through tests with and without include_project_item_owner_ids
      [false, true].each do |include_project_item_owner_ids|
        failure_message = "Test failed with include_project_item_owner_ids=#{include_project_item_owner_ids}"

        # 1) Query with redacted items assigned to user_stimpy
        response = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
        assert_max_query_count_per_table({ repositories: 1 }) do
          query = Search::Queries::MemexProjectItemQuery.new(
            project: @memex,
            viewer: @user,
            include_project_item_owner_ids:,
          )
          response = query.execute
        end

        # Two Elasticsearch query executions were made since redactions were required user_stimpy items
        assert_equal query_count += 2, GitHub.dogstats.increments("search.query.total").length, failure_message
        assert_same_elements [@public_repo.id, public_repo2.id], response&.redactor_results&.authorized_repo_ids, failure_message
        assert_same_elements [another_org_repo.id, private_repo.id], response&.redactor_results&.unauthorized_repo_ids, failure_message
        assert_same_elements expected_project_item_owner_ids, response&.project_item_owner_ids, failure_message if include_project_item_owner_ids
        assert_nil response&.project_item_owner_ids, failure_message unless include_project_item_owner_ids
        assert_equal 7, response&.total, failure_message

        # 2) Query without redacted items by filtering out items assigned to user_stimpy
        response = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
        assert_max_query_count_per_table({ repositories: 1 }) do
          query = Search::Queries::MemexProjectItemQuery.new(
            project: @memex,
            viewer: @user,
            query: "-assignee:#{user_stimpy.login}",
            include_project_item_owner_ids:,
          )
          response = query.execute
        end

        # Only one Elasticsearch query execution was made since we avoided redactions by filtering out user_stimpy items
        assert_equal query_count += 1, GitHub.dogstats.increments("search.query.total").length
        assert_same_elements [@public_repo.id, public_repo2.id], response&.redactor_results&.authorized_repo_ids, failure_message
        assert_same_elements [], response&.redactor_results&.unauthorized_repo_ids, failure_message
        assert_same_elements expected_project_item_owner_ids, response&.project_item_owner_ids, failure_message if include_project_item_owner_ids
        assert_nil response&.project_item_owner_ids, failure_message unless include_project_item_owner_ids
        assert_equal 5, response&.total, failure_message

        # 3) Query with redacted items by filtering on items assigned to user_stimpy (some are redacted)
        response = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
        assert_max_query_count_per_table({ repositories: 1 }) do
          query = Search::Queries::MemexProjectItemQuery.new(
            project: @memex,
            viewer: @user,
            query: "assignee:#{user_stimpy.login}",
            include_project_item_owner_ids:,
          )
          response = query.execute
        end

        # Two Elasticsearch query executions were made since some user_stimpy items are redacted
        assert_equal query_count += 2, GitHub.dogstats.increments("search.query.total").length
        assert_same_elements [@public_repo.id], response&.redactor_results&.authorized_repo_ids, failure_message
        assert_same_elements [another_org_repo.id, private_repo.id], response&.redactor_results&.unauthorized_repo_ids, failure_message
        assert_same_elements expected_project_item_owner_ids, response&.project_item_owner_ids, failure_message if include_project_item_owner_ids
        assert_nil response&.project_item_owner_ids, failure_message unless include_project_item_owner_ids
        assert_equal 2, response&.total, failure_message

        # Loop through tests with and without include_empty_slices (nested within loop for with or without include_project_item_owner_ids)
        [false, true].each do |include_empty_slices|
          failure_message = "Test failed with include_project_item_owner_ids=#{include_project_item_owner_ids} and include_empty_slices=#{include_empty_slices}"

          # 4) Slice on Assignees, with no slice_value (requires redactions)
          response = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
          assert_max_query_count_per_table({ repositories: 1 }) do
            query = Search::Queries::MemexProjectItemQuery.new(
              project: @memex,
              viewer: @user,
              include_project_item_owner_ids:,
              slice_by: assignee_col_id,
              include_empty_slices:,
            )
            response = query.execute
          end

          # No filtering, so all slices have non-zero values
          expected_slice_values = [user_drafter.login, user_ren.login, user_stimpy.login, MISSING_VALUE_GROUP_KEY]
          expected_sorted_slice_counts = [1, 4, 2, 1]

          # Two Elasticsearch query executions were made since redactions were required for user_stimpy slice counts
          assert_equal query_count += 2, GitHub.dogstats.increments("search.query.total").length, failure_message
          assert_same_elements [@public_repo.id, public_repo2.id], response&.redactor_results&.authorized_repo_ids, failure_message
          assert_same_elements [another_org_repo.id, private_repo.id], response&.redactor_results&.unauthorized_repo_ids, failure_message
          assert_same_elements expected_project_item_owner_ids, response&.project_item_owner_ids, failure_message if include_project_item_owner_ids
          assert_nil response&.project_item_owner_ids, failure_message unless include_project_item_owner_ids
          assert_equal expected_slice_values, response&.slices&.map { |s| s["slice_value"] }, failure_message
          assert_equal expected_sorted_slice_counts, response&.slices&.map { |s| s["total_count"] }, failure_message
          assert_equal 7, response&.total, failure_message

          # 5) Slice on Assignees, with a slice_value of user_stimpy (requires redactions)
          response = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
          assert_max_query_count_per_table({ repositories: 1 }) do
            query = Search::Queries::MemexProjectItemQuery.new(
              project: @memex,
              viewer: @user,
              include_project_item_owner_ids:,
              slice_by: assignee_col_id,
              slice_value: user_stimpy.login,
              include_empty_slices:,
            )
            response = query.execute
          end

          # Two Elasticsearch query executions were made since redactions were required for user_stimpy slice counts
          assert_equal query_count += 2, GitHub.dogstats.increments("search.query.total").length, failure_message
          assert_same_elements [@public_repo.id, public_repo2.id], response&.redactor_results&.authorized_repo_ids, failure_message
          assert_same_elements [another_org_repo.id, private_repo.id], response&.redactor_results&.unauthorized_repo_ids, failure_message
          assert_same_elements expected_project_item_owner_ids, response&.project_item_owner_ids, failure_message if include_project_item_owner_ids
          assert_nil response&.project_item_owner_ids, failure_message unless include_project_item_owner_ids
          assert_equal expected_slice_values, response&.slices&.map { |s| s["slice_value"] }, failure_message
          assert_equal expected_sorted_slice_counts, response&.slices&.map { |s| s["total_count"] }, failure_message
          assert_equal 2, response&.total, failure_message

          # 6) Slice on Assignees, with a slice_value of user_stimpy, filtered on visible @public_repo (redactions if include_empty_slices)
          rresponse = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
          assert_max_query_count_per_table({ repositories: 1 }) do
            query = Search::Queries::MemexProjectItemQuery.new(
              project: @memex,
              viewer: @user,
              query: "#{@public_repo.owner.name}/#{@public_repo.name}",
              include_project_item_owner_ids:,
              slice_by: assignee_col_id,
              slice_value: user_stimpy.login,
              include_empty_slices:,
            )
            response = query.execute
          end

          # Filtering on the visible repo, so now the draft issue becomes an empty slice
          expected_slice_values = [user_ren.login, user_stimpy.login, MISSING_VALUE_GROUP_KEY]
          expected_sorted_slice_counts = [3, 2, 1]
          expected_authorized_repo_ids = [@public_repo.id]
          expected_unauthorized_repo_ids = []
          if include_empty_slices
            expected_slice_values << user_drafter.login
            expected_sorted_slice_counts << 0
            expected_authorized_repo_ids << public_repo2.id
            expected_unauthorized_repo_ids += [another_org_repo.id, private_repo.id]
          end

          # Redactions required only if include_empty_slices
          expected_es_queries = include_empty_slices ? 2 : 1
          assert_equal query_count += expected_es_queries, GitHub.dogstats.increments("search.query.total").length, failure_message
          assert_same_elements expected_authorized_repo_ids, response&.redactor_results&.authorized_repo_ids, failure_message
          assert_same_elements expected_unauthorized_repo_ids, response&.redactor_results&.unauthorized_repo_ids, failure_message
          assert_same_elements expected_project_item_owner_ids, response&.project_item_owner_ids, failure_message if include_project_item_owner_ids
          assert_nil response&.project_item_owner_ids, failure_message unless include_project_item_owner_ids
          assert_equal expected_slice_values, response&.slices&.map { |s| s["slice_value"] }, failure_message
          assert_equal expected_sorted_slice_counts, response&.slices&.map { |s| s["total_count"] }, failure_message
          assert_equal 2, response&.total, failure_message

          # 7) Slice on Assignees, with a slice_value of user_ren, filtered on visible @public_repo (redactions if include_empty_slices)
          response = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
          assert_max_query_count_per_table({ repositories: 1 }) do
            query = Search::Queries::MemexProjectItemQuery.new(
              project: @memex,
              viewer: @user,
              query: "#{@public_repo.owner.name}/#{@public_repo.name}",
              include_project_item_owner_ids:,
              slice_by: assignee_col_id,
              slice_value: user_ren.login,
              include_empty_slices:,
            )
            response = query.execute
          end

          # Redactions required only if include_empty_slices
          expected_es_queries = include_empty_slices ? 2 : 1
          assert_equal query_count += expected_es_queries, GitHub.dogstats.increments("search.query.total").length, failure_message
          assert_same_elements expected_authorized_repo_ids, response&.redactor_results&.authorized_repo_ids, failure_message
          assert_same_elements expected_unauthorized_repo_ids, response&.redactor_results&.unauthorized_repo_ids, failure_message
          assert_same_elements expected_project_item_owner_ids, response&.project_item_owner_ids, failure_message if include_project_item_owner_ids
          assert_nil response&.project_item_owner_ids, failure_message unless include_project_item_owner_ids
          assert_equal expected_slice_values, response&.slices&.map { |s| s["slice_value"] }, failure_message
          assert_equal expected_sorted_slice_counts, response&.slices&.map { |s| s["total_count"] }, failure_message
          assert_equal 3, response&.total, failure_message
        end
      end
    end
  end

  context "spam redactions" do
    test "omits project items created by spammy users", spammy_only: true do
      populate_elasticsearch_index!(@non_spammy_items + [@spammy_item, @spammy_draft_item])

      response = T.let(nil, T.nilable(Search::Responses::MemexProjectItemResponse))
      # Ensure we efficiently query the User table once
      assert_max_query_count_per_table({ users: 1 }) do
        query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
      )
        response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)
      end

      # Two Elasticsearch query executions were made since redactions were required for spammy items
      assert_equal 2, GitHub.dogstats.increments("search.query.total").length
      assert_same_elements @non_spammy_items.map { _1.id }, response&.model_ids
    end

    test "omits project items with issue and pull request content created by spammy users", spammy_only: true do
      populate_elasticsearch_index!(@non_spammy_items + [@item_with_spammy_issue, @item_with_spammy_pull_request])

      response = T.let(nil, T.nilable(Search::Responses::MemexProjectItemResponse))
      # Ensure we efficiently query the User table once
      assert_max_query_count_per_table({ users: 1 }) do
        query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
      )
        response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)
      end

      # Two Elasticsearch query executions were made since redactions were required for spammy content
      assert_equal 2, GitHub.dogstats.increments("search.query.total").length
      assert_same_elements @non_spammy_items.map { _1.id }, response&.model_ids
    end
  end

  test "omits spammy project items and spammy project content (issue and pull request) created by spammy users", spammy_only: true do
    all_spammy_items = [@spammy_item, @spammy_draft_item, @item_with_spammy_issue, @item_with_spammy_pull_request]
    all_non_spammy_items = @non_spammy_items + [@non_spammy_draft_item]

    populate_elasticsearch_index!(all_spammy_items + all_non_spammy_items)

    response = T.let(nil, T.nilable(Search::Responses::MemexProjectItemResponse))
    # Ensure we efficiently query the User table once
    assert_max_query_count_per_table({ users: 1 }) do
      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
      )
      response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)
    end

    # Two Elasticsearch query executions were made since redactions were required for spammy content
    assert_equal 2, GitHub.dogstats.increments("search.query.total").length
    assert_same_elements all_non_spammy_items.map { _1.id }, response&.model_ids
  end

  test "omits the same spammy items as the legacy remove_spam param used with paged item spam removal", spammy_only: true do
    all_spammy_items = [@spammy_item, @spammy_draft_item, @item_with_spammy_issue, @item_with_spammy_pull_request]
    all_non_spammy_items = @non_spammy_items + [@non_spammy_draft_item]

    populate_elasticsearch_index!(all_spammy_items + all_non_spammy_items)

    # Ensure we efficiently query the User table once
    query = Search::Queries::MemexProjectItemQuery.new(
      project: @memex.reload,
      viewer: @user,
      remove_spam: false,
    )
    response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)

    GitHub.flipper[:memex_mwl_spam_redaction].disable
    # Ensure we efficiently query the User table once
    query = Search::Queries::MemexProjectItemQuery.new(
      project: @memex.reload,
      viewer: @user,
      remove_spam: true,
    )
    legacy_response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)

    # The legacy remove_spam only removes from the item models method, not the model_ids method
    legacy_response_non_spammy_ids = legacy_response.models.map { _1.id }

    assert_same_elements all_non_spammy_items.map { _1.id }, response.model_ids
    assert_same_elements response.model_ids, legacy_response_non_spammy_ids
  end

  test "does not omit spammy items or spammy content for site admins", spammy_only: true do
    all_spammy_items = [@spammy_item, @spammy_draft_item, @item_with_spammy_issue, @item_with_spammy_pull_request]
    all_non_spammy_items = @non_spammy_items + [@non_spammy_draft_item]

    populate_elasticsearch_index!(all_spammy_items + all_non_spammy_items)

    response = T.let(nil, T.nilable(Search::Responses::MemexProjectItemResponse))
    # Ensure we efficiently query the User table once
    assert_max_query_count_per_table({ users: 1 }) do
      query = Search::Queries::MemexProjectItemQuery.new(
      project: @memex.reload,
      viewer: @site_admin_member,
    )
      response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)
    end

    # One Elasticsearch query execution was made since no redactions for site admins
    assert_equal 1, GitHub.dogstats.increments("search.query.total").length

    # Site admins see all items, spammy or not
    expected_item_ids = (all_non_spammy_items + all_spammy_items).map { _1.id }
    assert_same_elements expected_item_ids, response&.model_ids
  end

  test "does not omit spammy items or spammy content if memex_mwl_spam_redaction is disabled", spammy_only: true do
    all_spammy_items = [@spammy_item, @spammy_draft_item, @item_with_spammy_issue, @item_with_spammy_pull_request]
    all_non_spammy_items = @non_spammy_items + [@non_spammy_draft_item]
    GitHub.flipper[:memex_mwl_spam_redaction].disable

    populate_elasticsearch_index!(all_spammy_items + all_non_spammy_items)

    response = T.let(nil, T.nilable(Search::Responses::MemexProjectItemResponse))
    # Ensure we efficiently query the User table once
    assert_max_query_count_per_table({ users: 1 }) do
      query = Search::Queries::MemexProjectItemQuery.new(
      project: @memex.reload,
      viewer: @user,
    )
      response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)
    end

    # One Elasticsearch query execution was made since no redactions were performed
    assert_equal 1, GitHub.dogstats.increments("search.query.total").length

    # No spammy redactions
    expected_item_ids = (all_non_spammy_items + all_spammy_items).map { _1.id }
    assert_same_elements expected_item_ids, response&.model_ids
  end

  test "does not omit spammy items for creators of those items or item content", spammy_only: true do
    all_spammy_items = [@spammy_item, @spammy_draft_item, @item_with_spammy_issue, @item_with_spammy_pull_request]
    all_non_spammy_items = @non_spammy_items + [@non_spammy_draft_item]

    spammy_user_items, other_spammy_items = all_spammy_items.partition do |i|
      i.creator_id == @spammy_user.id ||
      (i.content_type != "DraftIssue" && i.content&.user_id == @spammy_user.id)
    end
    refute_empty spammy_user_items
    refute_empty other_spammy_items

    populate_elasticsearch_index!(all_spammy_items + all_non_spammy_items)

    response = T.let(nil, T.nilable(Search::Responses::MemexProjectItemResponse))
    # Ensure we efficiently query the User table once
    assert_max_query_count_per_table({ users: 1 }) do
      query = Search::Queries::MemexProjectItemQuery.new(
      project: @memex.reload,
      viewer: @spammy_user,
    )
      response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)
    end

    # Two Elasticsearch query executions were made since redactions were required for spammy_user2 spammy content
    assert_equal 2, GitHub.dogstats.increments("search.query.total").length

    # Spammy users see their own spammy items
    expected_item_ids = (all_non_spammy_items + spammy_user_items).map { _1.id }
    assert_same_elements expected_item_ids, response&.model_ids
  end

  test "omits spammy items when other query filters are applied", spammy_only: true do
    all_spammy_items = [@spammy_item, @spammy_draft_item, @item_with_spammy_issue, @item_with_spammy_pull_request]
    all_non_spammy_items = @non_spammy_items + [@non_spammy_draft_item]

    populate_elasticsearch_index!(all_spammy_items + all_non_spammy_items)

    response = T.let(nil, T.nilable(Search::Responses::MemexProjectItemResponse))
    # Ensure we efficiently query the User table once
    assert_max_query_count_per_table({ users: 1 }) do
      query = Search::Queries::MemexProjectItemQuery.new(
      project: @memex.reload,
      viewer: @user,
      query: "-assignee:#{@ten_non_spammy_users[0].login},#{@ten_non_spammy_users[1].login}",
    )
      response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)
    end

    # Two Elasticsearch query executions were made since redactions were required for spammy content
    assert_equal 2, GitHub.dogstats.increments("search.query.total").length

    # We filtered out the first two non-spammy items
    expected_item_ids = all_non_spammy_items.values_at(2, 3, 4, 5).map { _1.id }
    assert_same_elements expected_item_ids, response&.model_ids
  end

  test "omits spammy items and redacts unauthorized items in the same Elasticsearch request", spammy_only: true, es_8_only: true do
    private_repo_admin = create(:user)
    private_repo = create(:private_repository, owner: private_repo_admin)
    another_org_repo = create(:private_repository, :org_owned)
    public_repo2 = create(:public_repository)

    user_ren = create(:verified_user, login: "ren")
    user_stimpy = create(:verified_user, login: "stimpy")
    user_drafter = create(:verified_user, login: "drafter")
    private_repo.add_member(user_stimpy)
    another_org_repo.add_member(user_stimpy)
    public_repo2.add_member(user_ren)
    @public_repo.add_member(user_ren)
    @public_repo.add_member(user_stimpy)

    assignee_col_id = @memex.columns.find(&:assignees?)&.id

    items = Array[create(:memex_project_item, content: create(:issue, repository: @public_repo), memex_project: @memex)] #0
    items << create(:memex_project_item, content: create(:issue, assignees: [user_stimpy], repository: another_org_repo), memex_project: @memex) #1 - redacted another_org_repo
    items << create(:memex_project_item, content: create(:issue, assignees: [user_stimpy], repository: private_repo), memex_project: @memex) #2 - redacted private_repo
    items << create(:memex_project_item, content: create(:issue, assignees: [user_ren], repository: @public_repo), memex_project: @memex) #3
    items << create(:memex_project_item, content: create(:issue, assignees: [user_ren], repository: @public_repo), memex_project: @memex) #4
    items << create(:memex_project_item, content: create(:issue, assignees: [user_ren, user_stimpy], repository: @public_repo), memex_project: @memex) #5
    items << create(:memex_project_item, content: create(:issue, assignees: [user_stimpy], repository: @public_repo), memex_project: @memex) #6
    items << create(:memex_project_item, content: create(:draft_issue).tap { |d| d.update!(assignees: [user_drafter]) }, memex_project: @memex) #7 - draft issue
    items << create(:memex_project_item, content: create(:issue, assignees: [user_ren], repository: public_repo2), memex_project: @memex) #8 - public_repo

    expected_authorized_items = items.values_at(0, 3, 4, 5, 6, 7, 8) # omit the unauthorized items at index 1 and 2

    all_spammy_items = [@spammy_item, @spammy_draft_item, @item_with_spammy_issue, @item_with_spammy_pull_request]
    all_non_spammy_items = @non_spammy_items + [@non_spammy_draft_item]

    populate_elasticsearch_index!(all_spammy_items + all_non_spammy_items + items)

    query_count = 0

    # 1) Query that includes spammy and unauthorized items to redact
    query = Search::Queries::MemexProjectItemQuery.new(
      project: @memex.reload,
      viewer: @user,
    )
    response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)

    # Two Elasticsearch query executions were made since redactions were required for spammy content and for unauthorized content
    assert_equal query_count += 2, GitHub.dogstats.increments("search.query.total").length

    # Expect only non-spammy, authorized items
    expected_item_ids = (all_non_spammy_items + expected_authorized_items).map { _1.id }
    assert_same_elements expected_item_ids, response.model_ids

    # Expect the redactor results to include spam processing and authorized repository information.
    expected_authorized_repo_ids = [@public_repo.id, @spammy_item.repository_id, public_repo2.id]
    expected_unauthorized_repo_ids = [private_repo.id, another_org_repo.id]
    assert_same_elements expected_authorized_repo_ids, response.redactor_results&.authorized_repo_ids
    assert_same_elements expected_unauthorized_repo_ids, response.redactor_results&.unauthorized_repo_ids
    assert response.redactor_results&.checked_for_spam

    # 2) Slice on Assignees, with a slice_value of user_stimpy.
    #    This requires a global aggregation for all slice values, and includes spammy and auth redactions.
    query = Search::Queries::MemexProjectItemQuery.new(
      project: @memex,
      viewer: @user,
      slice_by: assignee_col_id,
      slice_value: user_stimpy.login
    )
    response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)

    # Two Elasticsearch query executions were made since redactions were required for spammy content and for unauthorized content
    assert_equal query_count += 2, GitHub.dogstats.increments("search.query.total").length

    # Expect only non-spammy, authorized items and counts
    assert_equal 2, response.total

    # Slice values and counts do not include contributions from redacted items (hence only 2 for stimpy and no spammy items)
    # Default test non_spammy_users have login values "user-*"
    expected_assignees = [user_drafter, user_ren, user_stimpy] + @ten_non_spammy_users.first(5).sort_by(&:login)
    expected_slice_values = expected_assignees.map(&:login) << MISSING_VALUE_GROUP_KEY
    expected_sorted_slice_counts = [1, 4, 2] + [1, 1, 1, 1, 1] + [2]
    assert_equal expected_slice_values, response.slices&.map { |s| s["slice_value"] }
    assert_equal expected_sorted_slice_counts, response.slices&.map { |s| s["total_count"] }

    # Same expected redactor results as the previous query
    assert_same_elements expected_authorized_repo_ids, response.redactor_results&.authorized_repo_ids
    assert_same_elements expected_unauthorized_repo_ids, response.redactor_results&.unauthorized_repo_ids
    assert response.redactor_results&.checked_for_spam
  end

  test "avoids second Elasticsearch query if no spammy items match the query filter", spammy_only: true do
    all_spammy_items = [@spammy_item, @spammy_draft_item, @item_with_spammy_issue, @item_with_spammy_pull_request]
    all_non_spammy_items = @non_spammy_items + [@non_spammy_draft_item]

    populate_elasticsearch_index!(all_spammy_items + all_non_spammy_items)

    response = T.let(nil, T.nilable(Search::Responses::MemexProjectItemResponse))
    # Ensure we efficiently query the User table once
    assert_max_query_count_per_table({ users: 1 }) do
      query = Search::Queries::MemexProjectItemQuery.new(
      project: @memex.reload,
      viewer: @user,
      query: "assignee:#{@ten_non_spammy_users[0].login},#{@ten_non_spammy_users[1].login}",
    )
      response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)
    end

    # One Elasticsearch query execution was made since no need for redactions for spammy content
    assert_equal 1, GitHub.dogstats.increments("search.query.total").length

    # We filtered on only the first two non-spammy items
    expected_item_ids = all_non_spammy_items.values_at(0, 1).map { _1.id }
    assert_same_elements expected_item_ids, response&.model_ids
  end

  # Loop through slice tests with and without include_empty_slices.
  # When include_empty_slices is true, it requires a global aggregation with filtering and redactions applied there too.
  [false, true].each do |include_empty_slices|
    test "omits spammy items from slice values and counts, with include_empty_slices = #{include_empty_slices}", spammy_only: true do
      all_spammy_items = [@spammy_item, @spammy_draft_item, @item_with_spammy_issue, @item_with_spammy_pull_request]
      all_non_spammy_items = @non_spammy_items + [@non_spammy_draft_item]

      populate_elasticsearch_index!(all_spammy_items + all_non_spammy_items)

      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        slice_by: @comments_column.id,
        include_empty_slices:
      )
      response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)

      # Two Elasticsearch query executions were made since redactions were required for spammy content
      assert_equal 2, GitHub.dogstats.increments("search.query.total").length

      # Spammy and non-spammy comment slice values
      spammy_comment_values = all_spammy_items.map { _1.column_value(@comments_column) || MISSING_VALUE_GROUP_KEY }.uniq.sort
      non_spammy_comment_values = all_non_spammy_items.map { _1.column_value(@comments_column) || MISSING_VALUE_GROUP_KEY }.uniq.sort
      assert_equal spammy_comment_values, ["Spammy draft item", "Spammy issue item", "Spammy item", "Spammy pull request item"]
      assert_equal non_spammy_comment_values, ["Legit issue item", "_noValue"]

      # Slice values and counts match only the non-spammy items
      assert_equal non_spammy_comment_values, response.slices&.map { |s| s["slice_value"] }
      assert_equal [5, 1], response.slices&.map { |s| s["total_count"] }
      assert_equal 6, response.total
    end

    test "omits spammy items from slice values and counts, with a slice value and include_empty_slices = #{include_empty_slices}", spammy_only: true do
      all_spammy_items = [@spammy_item, @spammy_draft_item, @item_with_spammy_issue, @item_with_spammy_pull_request]
      all_non_spammy_items = @non_spammy_items + [@non_spammy_draft_item]

      populate_elasticsearch_index!(all_spammy_items + all_non_spammy_items)

      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        slice_by: @comments_column.id,
        slice_value: "Legit issue item",
        include_empty_slices:
      )
      response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)

      # Two Elasticsearch query executions were made since the slice value requires a global aggregation for other slices, and those include spammy content
      assert_equal 2, GitHub.dogstats.increments("search.query.total").length

      non_spammy_comment_values = all_non_spammy_items.map { _1.column_value(@comments_column) || MISSING_VALUE_GROUP_KEY }.uniq.sort
      assert_equal non_spammy_comment_values, ["Legit issue item", "_noValue"]

      # Slice values and counts match only the non-spammy items, even whith a global aggregation
      assert_equal non_spammy_comment_values, response.slices&.map { |s| s["slice_value"] }
      assert_equal [5, 1], response.slices&.map { |s| s["total_count"] }
      assert_equal 5, response.total
    end

    test "omits spammy items from slice values and counts, with a filter, slice value and include_empty_slices = #{include_empty_slices}", spammy_only: true do
      all_spammy_items = [@spammy_item, @spammy_draft_item, @item_with_spammy_issue, @item_with_spammy_pull_request]
      all_non_spammy_items = @non_spammy_items + [@non_spammy_draft_item]

      populate_elasticsearch_index!(all_spammy_items + all_non_spammy_items)

      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "assignee:#{@ten_non_spammy_users[0].login},#{@ten_non_spammy_users[1].login}",
        slice_by: @comments_column.id,
        slice_value: "Legit issue item",
        include_empty_slices:
      )
      response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)

      # Spammy redactions required only if include_empty_slices since the filter on assignees includes only non-spammy items.
      expected_es_queries = include_empty_slices ? 2 : 1
      assert_equal expected_es_queries, GitHub.dogstats.increments("search.query.total").length

      expected_non_spammy_slice_values = include_empty_slices ? ["Legit issue item", "_noValue"] : ["Legit issue item"]
      expected_non_spammy_slice_counts = include_empty_slices ? [2, 0] : [2]

      # Slice values and counts match only the non-spammy items, even whith a global aggregation
      assert_equal expected_non_spammy_slice_values, response.slices&.map { |s| s["slice_value"] }
      assert_equal expected_non_spammy_slice_counts, response.slices&.map { |s| s["total_count"] }
      assert_equal 2, response.total
    end
  end
end
