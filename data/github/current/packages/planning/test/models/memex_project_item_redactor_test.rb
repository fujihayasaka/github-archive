# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectItemRedactorTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper
  include IssuesGraphTestHelpers
  include GitHub::LoggerHelper
  include DogstatsTestHelpers

  fixtures do
    @admin = create(:verified_user)
    @org = create(:organization, admin: @admin)
    @memex = create(:memex_project, owner: @org, creator: @admin)

    # Spammy member (updated as spammy a few lines down)
    @spammy_user = create(:verified_user)
    @spammy_user.emails.first.verify!
    @org.add_member(@spammy_user)

    # Ordinary member
    @member = create(:verified_user)
    @org.add_member(@member)

    # Site admin viewer
    @site_admin = create(:staff_admin_user)
    @org.add_member(@site_admin)

    @repo = create(:public_repository, from_example: :repository_test_simple)
    @issue = create(:issue, repository: @repo)
    @pull = create(:pull_request, :disable_disk_access, repository: @repo)

    @private_repo_admin = create(:user)
    @private_repo = create(:private_repository, owner: @private_repo_admin)
    @private_issue = create(:issue, repository: @private_repo, user: @private_repo_admin)
    @private_pull = create(:pull_request, :disable_disk_access, repository: @private_repo, user: @private_repo_admin)

    # Allow the @spammy_user to create a valid pull request before updating them as spammy.
    # Else, you'll later get this error - ActiveRecord::RecordInvalid: Validation failed: Pull request author can't be blank
    # Then we need to explicitly mark the pull request and parent issue as spammy.
    spammy_pull_issue = create(:issue, repository: @repo, user: @spammy_user)
    @spammy_pull = create(:pull_request, :with_mergeable_head, :merged, repository: @repo, user: @spammy_user, issue: spammy_pull_issue)
    @spammy_user.update(spammy: true)
    @spammy_pull.update_column(:user_hidden, true)
    @spammy_pull.issue.update_column(:user_hidden, true)

    # Org 2 used for testing CAP redactions for column values like linked PRs that target the repository owner
    @org2 = create(:organization, admin: @admin)
    @repo2 = create(:public_repository, owner: @org2, from_example: :repository_test_simple)
    @pull2 = create(:pull_request, :with_mergeable_head, :merged, repository: @repo2)

    # Linked pull requests with varying visibility to test column value redactions
    @issue_with_4_linked_prs = create(:issue, repository: @repo)
    create(:close_issue_reference, issue: @issue_with_4_linked_prs, pull_request: @pull)
    create(:close_issue_reference, issue: @issue_with_4_linked_prs, pull_request: @pull2)
    create(:close_issue_reference, issue: @issue_with_4_linked_prs, pull_request: @private_pull)
    create(:close_issue_reference, issue: @issue_with_4_linked_prs, pull_request: @spammy_pull)
    @memex.default_view.make_column_visible!(@memex.columns.find(&:linked_pull_requests?))

    # create issues which have parents based on a scenarios that would elicit redaction
    @issue_with_normal_parent = create(:issue, repository: @repo)
    @issue_with_cap_restricted_parent = create(:issue, repository: @repo2)
    @issue_with_spammy_parent = create(:issue, repository: @repo)
    @issue_with_private_parent = create(:issue, repository: @private_repo)

    @normal_parent = create(:issue, repository: @repo)
    @normal_parent.add_sub_issue!(@issue_with_normal_parent, @admin.id)
    @cap_restricted_parent = create(:issue, repository: @repo2)
    @cap_restricted_parent .add_sub_issue!(@issue_with_cap_restricted_parent, @admin.id)
    @spammy_parent = create(:issue, repository: @repo, user: @spammy_user)
    @spammy_parent.add_sub_issue!(@issue_with_spammy_parent, @admin.id)
    @private_parent = create(:issue, repository: @private_repo, user: @private_repo_admin)
    @private_parent.add_sub_issue!(@issue_with_private_parent, @admin.id)
    @memex.default_view.make_column_visible!(@memex.columns.find(&:parent_issue?))

    # Memex items
    @spammy_item = create(:memex_project_item, :with_denormalized_title, memex_project: @memex, creator: @spammy_user)
    @issue_item = create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: @issue)
    @issue_item_with_4_linked_prs = create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: @issue_with_4_linked_prs)
    @pull_item = create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: @pull)
    @private_issue_item = create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: @private_issue)
    @private_pull_item = create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: @private_pull)
    @items_with_parents = [
      create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: @issue_with_normal_parent),
      create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: @issue_with_cap_restricted_parent),
      create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: @issue_with_spammy_parent),
      create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: @issue_with_private_parent),
    ]
    @items_with_parents.freeze
  end

  setup do
    enable_feature_flag(:memex_use_mwl_redactions)
  end

  context "#items" do
    test "redacts SSO protected issues that the viewer can see" do
      redactor = MemexProjectItemRedactor.new(viewer: @admin, items: [@issue_item, @pull_item], cap_filter: cap_authorizing_filter([@pull_item]))

      assert_equal MemexProjectItem::REDACTED_ITEM_TYPE, redactor.items.first.content_type
      refute_equal MemexProjectItem::REDACTED_ITEM_TYPE, redactor.items.second.content_type
    end

    test "redacts an issue that the viewer is not allowed to see" do
      redactor = MemexProjectItemRedactor.new(viewer: @admin, items: [@private_issue_item])
      result = assert_max_query_count_per_table({ issues: 1 }) { redactor.items }

      assert_equal MemexProjectItem::REDACTED_ITEM_TYPE, redactor.items.first.content_type
    end

    test "doesn't query the issues table" do
      redactor = MemexProjectItemRedactor.new(viewer: @admin, items: [@private_issue_item])

      # Assert that we haven't touched the `issues` table...
      result = assert_max_query_count_per_table({ issues: 1 }) { redactor.items }

      # ...but make sure redaction was still successful.
      assert_equal MemexProjectItem::REDACTED_ITEM_TYPE, result.first.content_type
    end

    test "redacts an issue that the viewer is not allowed to see when using denormalized data" do
      prefill_result = MemexProjectItemPrefiller.new(
        [@private_issue_item],
        columns: @memex.default_view.visible_columns,
        read_denormalized_title: true,
        title_column: @memex.columns.find(&:title?)
      ).prefill

      redactor = MemexProjectItemRedactor.new(
        viewer: @admin,
        items: [@private_issue_item],
        prefilled_associations: prefill_result
      )

      assert_equal MemexProjectItem::REDACTED_ITEM_TYPE, redactor.items.first.content_type
    end

    test "does not redact an issue that the viewer is allowed see" do
      redactor = MemexProjectItemRedactor.new(viewer: @admin, items: [@issue_item])
      refute_equal MemexProjectItem::REDACTED_ITEM_TYPE, redactor.items.first.content_type
    end

    test "does not redact an issue that the viewer is allowed see when using denormalized data" do

      prefill_result = MemexProjectItemPrefiller.new(
        [@issue_item],
        columns: @memex.default_view.visible_columns,
        read_denormalized_title: true,
        title_column: @memex.columns.find(&:title?)
      ).prefill

      redactor = MemexProjectItemRedactor.new(
        viewer: @admin,
        items: [@issue_item],
        prefilled_associations: prefill_result
      )

      refute_equal MemexProjectItem::REDACTED_ITEM_TYPE, redactor.items.first.content_type
    end

    test "redacts a pull request that the viewer is not allowed to see" do
      redactor = MemexProjectItemRedactor.new(viewer: @admin, items: [@private_pull_item])
      assert_equal MemexProjectItem::REDACTED_ITEM_TYPE, redactor.items.first.content_type
    end

    test "redacts a pull request that the viewer is not allowed to see when using denormalized data" do
      prefill_result = MemexProjectItemPrefiller.new(
        [@private_pull_item],
        columns: @memex.default_view.visible_columns,
        read_denormalized_title: true,
        title_column: @memex.columns.find(&:title?)
      ).prefill

      redactor = MemexProjectItemRedactor.new(
        viewer: @admin,
        items: [@private_pull_item],
        prefilled_associations: prefill_result
      )

      assert_equal MemexProjectItem::REDACTED_ITEM_TYPE, redactor.items.first.content_type
    end

    test "does not redact a pull request that the viewer is allowed to see" do
      redactor = MemexProjectItemRedactor.new(viewer: @admin, items: [@pull_item])
      refute_equal MemexProjectItem::REDACTED_ITEM_TYPE, redactor.items.first.content_type
    end

    test "does not redact a pull request that the viewer is allowed to see when using denormalized data" do
      prefill_result = MemexProjectItemPrefiller.new(
        [@pull_item],
        columns: @memex.default_view.visible_columns,
        read_denormalized_title: true,
        title_column: @memex.columns.find(&:title?)
      ).prefill

      redactor = MemexProjectItemRedactor.new(
        viewer: @admin,
        items: [@pull_item],
        prefilled_associations: prefill_result
      )

      refute_equal MemexProjectItem::REDACTED_ITEM_TYPE, redactor.items.first.content_type
    end

    test "does not redact a draft issue" do
      other_user = create(:verified_user)
      other_memex = create(:memex_project, owner: other_user)
      draft_issue_item = other_memex.build_draft_issue(creator: other_user, title: "A rough idea")
      draft_issue_item.save!

      redactor = MemexProjectItemRedactor.new(viewer: @admin, items: [draft_issue_item])
      refute_equal MemexProjectItem::REDACTED_ITEM_TYPE, redactor.items.first.content_type
    end

    test "does not redact a draft issue when using denormalized data" do
      other_user = create(:verified_user)
      other_memex = create(:memex_project, owner: other_user)
      draft_issue_item = other_memex.build_draft_issue(creator: other_user, title: "A rough idea")
      draft_issue_item.save!

      prefill_result = MemexProjectItemPrefiller.new(
        [draft_issue_item],
        columns: @memex.default_view.visible_columns,
        read_denormalized_title: true,
        title_column: @memex.columns.find(&:title?)
      ).prefill

      redactor = MemexProjectItemRedactor.new(
        viewer: @admin,
        items: [draft_issue_item],
        prefilled_associations: prefill_result
      )

      refute_equal MemexProjectItem::REDACTED_ITEM_TYPE, redactor.items.first.content_type
    end

    test "passes each given item through the redaction process" do
      redactor = MemexProjectItemRedactor.new(
        viewer: @admin,
        items: [@private_issue_item, @issue_item, @private_pull_item]
      )

      assert_equal(
        [MemexProjectItem::REDACTED_ITEM_TYPE, "Issue", MemexProjectItem::REDACTED_ITEM_TYPE],
        redactor.items.map(&:content_type)
      )
    end

    test "does not make any queries when redacting items with prefilled associations" do
      items = [@private_issue_item, @issue_item, @private_pull_item]
      prefill_result = MemexProjectItem::PrefilledAssociations.new

      redactor = MemexProjectItemRedactor.new(
        viewer: @admin,
        items: items,
        prefilled_associations: prefill_result
      )

      # Allow one query for visible issue IDs, but no more (i.e. no queries to load content).
      assert_max_query_count_per_table({ issues: 1, pull_requests: 0 }) do
        assert_equal(
          [MemexProjectItem::REDACTED_ITEM_TYPE, "Issue", MemexProjectItem::REDACTED_ITEM_TYPE],
          redactor.items.map(&:content_type)
        )
      end
    end

    test "redacts a linked pull request that the viewer is not allowed to see (non-denormalized data)" do
      prefill_result = MemexProjectItemPrefiller.new([@issue_item_with_4_linked_prs], columns: @memex.default_view.visible_columns).prefill
      redactor = MemexProjectItemRedactor.new(viewer: @admin, items: [@issue_item_with_4_linked_prs], columns: @memex.default_view.visible_columns)

      # Note: to support denormalized values, Spammy linked PRs are not redacted
      expected = [@private_pull.issue.id]

      assert_max_query_count_per_table({ issues: 1 }) { redactor.redacted_issue_ids }
      assert_same_elements expected, redactor.redacted_issue_ids
    end

    test "redacts a linked pull request that the viewer is not allowed to see when using denormalized data" do
      prefill_result = MemexProjectItemPrefiller.new(
        [@issue_item_with_4_linked_prs],
        columns: @memex.default_view.visible_columns,
        read_denormalized_title: true,
        title_column: @memex.columns.find(&:title?)
      ).prefill

      redactor = MemexProjectItemRedactor.new(
        viewer: @admin,
        items: [@issue_item_with_4_linked_prs],
        columns: @memex.default_view.visible_columns,
        prefilled_associations: prefill_result
      )

      # Note: to support denormalized values, Spammy linked PRs are not redacted
      expected = [@private_pull.issue.id]

      assert_max_query_count_per_table({ issues: 1 }) { redactor.redacted_issue_ids }
      assert_same_elements expected, redactor.redacted_issue_ids
    end

    test "redacts Conditional Access Policy SSO protected linked pull requests that the viewer can see" do
      prefill_result = MemexProjectItemPrefiller.new(
        [@issue_item_with_4_linked_prs],
        columns: @memex.default_view.visible_columns,
        read_denormalized_title: true,
        title_column: @memex.columns.find(&:title?)
      ).prefill

      pull2_cap_target = @pull2.issue.repository.owner

      redactor = MemexProjectItemRedactor.new(
        viewer: @admin,
        items: [@issue_item_with_4_linked_prs],
        columns: @memex.default_view.visible_columns,
        prefilled_associations: prefill_result,
        cap_filter: cap_authorizing_filter([pull2_cap_target])
      )

      expected = [@pull.issue.id, @private_pull.issue.id, @spammy_pull.issue.id]

      assert_max_query_count_per_table({ issues: 1 }) { redactor.redacted_issue_ids }
      assert_same_elements expected, redactor.redacted_issue_ids
    end

    test "redacts a parent issue that the viewer is not allowed to see (non-denormalized data)" do
      prefill_result = MemexProjectItemPrefiller.new(@items_with_parents, columns: @memex.default_view.visible_columns).prefill
      redactor = MemexProjectItemRedactor.new(viewer: @admin, items: @items_with_parents, columns: @memex.default_view.visible_columns)

      # Note: to support denormalized values, Spammy parents are not redacted
      expected = [@private_parent.id]

      assert_max_query_count_per_table({ issues: 1 }) { redactor.redacted_issue_ids }
      assert_same_elements expected, redactor.redacted_issue_ids
    end

    test "redacts a parent issue that the viewer is not allowed to see (non-denormalized data) when it's the only visible field" do
      @memex.default_view.update!(visible_fields: [@memex.columns.find(&:parent_issue?).id])

      prefill_result = MemexProjectItemPrefiller.new(@items_with_parents, columns: @memex.default_view.visible_columns).prefill
      redactor = MemexProjectItemRedactor.new(viewer: @admin, items: @items_with_parents, columns: @memex.default_view.visible_columns)

      expected = [@private_parent.id]

      assert_max_query_count_per_table({ issues: 1 }) { redactor.redacted_issue_ids }
      assert_same_elements expected, redactor.redacted_issue_ids
    end

    test "redacts a parent issue that the viewer is not allowed to see when using denormalized data" do
      prefill_result = MemexProjectItemPrefiller.new(
        @items_with_parents,
        columns: @memex.default_view.visible_columns,
        read_denormalized_title: true,
        title_column: @memex.columns.find(&:title?)
      ).prefill

      redactor = MemexProjectItemRedactor.new(
        viewer: @admin,
        items: @items_with_parents,
        columns: @memex.default_view.visible_columns,
        prefilled_associations: prefill_result
      )

      # Note: to support denormalized values, Spammy parent issues are not redacted
      expected = [@private_parent.id]

      assert_max_query_count_per_table({ issues: 1 }) { redactor.redacted_issue_ids }
      assert_same_elements expected, redactor.redacted_issue_ids
    end

    test "redacts Conditional Access Policy SSO protected parent issues that the viewer can see" do
      prefill_result = MemexProjectItemPrefiller.new(
        @items_with_parents,
        columns: @memex.default_view.visible_columns,
        read_denormalized_title: true,
        title_column: @memex.columns.find(&:title?)
      ).prefill

      cap_owner = @cap_restricted_parent.repository.owner

      redactor = MemexProjectItemRedactor.new(
        viewer: @admin,
        items: @items_with_parents,
        columns: @memex.default_view.visible_columns,
        prefilled_associations: prefill_result,
        cap_filter: cap_authorizing_filter([cap_owner])
      )

      expected = [@normal_parent.id, @private_parent.id, @spammy_parent.id]

      assert_max_query_count_per_table({ issues: 1 }) { redactor.redacted_issue_ids }
      assert_same_elements expected, redactor.redacted_issue_ids
    end

    test "redacts the tracked items that a viewer doesn't have access to without N+1", skip_enterprise: true do
      issue_graph_client = stub_issues_graph_client!
      enable_feature_flag(:repo_dependency_all_repo_grant_refactor)
      enable_feature_flag(:tasklist_block)
      disable_feature_flag(:optimize_single_memex_hierarchy_prefill)
      enable_feature_flag(:project_hierarchy_columns)
      disable_feature_flag(:issues_graph_api_disable_denormalized_read)
      disable_feature_flag(:memex_increased_issues_graph_timeouts)
      disable_feature_flag(:memex_table_without_limits)
      disable_feature_flag(:memex_project_without_limits_public_beta)
      # required to get consistent `abilities` query count below
      disable_feature_flag(:bypass_oopfs_query)
      disable_feature_flag(:bypass_oopfs_query_org)
      disable_feature_flag(:check_business_team_in_associated_repository_ids)

      # create another parent issue from another private issue
      private_repo_admin2 = create(:user)
      private_repo2 = create(:private_repository, owner: private_repo_admin2)
      private_issue2 = create(:issue, repository: private_repo2, user: private_repo_admin2)
      private_pull2 = create(:pull_request, :disable_disk_access, repository: private_repo2, user: private_repo_admin2)

      # create a child, and return the 2 parent issues as the trackedBy parents for their respective child items
      issue2 = create(:issue, repository: @repo)
      issue_item2 = create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: issue2)

      issue3 = create(:issue, repository: @repo)
      issue_item3 = create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: issue3)

      private_repo_admin3 = create(:user)
      private_repo3 = create(:private_repository, owner: private_repo_admin3)
      private_issue3 = create(:issue, repository: private_repo3, user: private_repo_admin3)

      issue_graph_client.expects(:get_project_tracked_by_items)
        .with(has_entries(owner_id: @memex.owner_id, item_id: @memex.id))
        .returns(as_tracked_by_items_result([
          {
            key: { ownerId: @issue_item.repository.owner_id, itemId: @issue_item.content.id },
            trackedByItems: [@private_issue.to_hierarchy_model]
          },
          {
            key: { ownerId: issue_item2.repository.owner_id, itemId: issue_item2.content.id },
            trackedByItems: [private_issue2.to_hierarchy_model]
          },
          {
            key: { ownerId: issue_item3.repository.owner_id, itemId: issue_item3.content.id },
            trackedByItems: [private_issue3.to_hierarchy_model]
          }
        ]))
      prefill_result = MemexProjectItemPrefiller.new(
        [@issue_item, issue_item2, issue_item3],
        read_denormalized_title: true,
        columns: [@memex.columns.find(&:tracked_by?)],
        title_column: @memex.columns.find(&:title?)
      ).prefill
      redactor = MemexProjectItemRedactor.new(viewer: @admin, items: [@issue_item, issue_item2, issue_item3], prefilled_associations: prefill_result)

      # ability checks take 7 queries, so make sure we are only making those 7 queries for the collective items as opposed
      # to 7 times per item
      count = TestEnv.test_all_features? ? 6 : 7 # FF bus_ids_exclude_billing_manager_valid_license reduces the queries
      assert_query_count_per_table({ abilities: count, issues: 0, repositories: 5 }) do
        assert_equal [@private_issue.id, private_issue2.id, private_issue3.id], redactor.redacted_issue_ids
      end
    end

    test "traces the items method" do
      MemexProjectItemRedactor.new(viewer: @admin, items: [@private_issue_item]).items

      refute_nil span = find_span_by(name: "memex_project_item_redactor#items")
      assert_same_hash(
        {
          "gh.memex.redactor.input_height" => 1,
          "gh.memex.redactor.input_height_bucket" => "xs",
          "gh.memex.redactor.output_height" => 0,
          "gh.memex.redactor.output_height_bucket" => "xs",
          "gh.memex.redactor.has_prefilled_associations" => false,
          "gh.memex.redactor.has_cap_filter" => false,
        },
        span.attributes
      )
    end

    test "traces the redacted_issue_ids method" do
      redactor = MemexProjectItemRedactor.new(
        viewer: @admin,
        items: [@issue_item_with_4_linked_prs],
        columns: @memex.default_view.visible_columns,
        cap_filter: cap_authorizing_filter([@pull2.issue.repository.owner])
      )
      redactor.redacted_issue_ids

      refute_nil span = find_span_by(name: "memex_project_item_redactor#redacted_issue_ids")
      assert_same_hash(
        {
          "gh.memex.redactor.has_linked_pull_requests_field" => true,
          "gh.memex.redactor.output_height" => 3,
          "gh.memex.redactor.output_height_bucket" => "xs",
        },
        span.attributes
      )
    end

    test "query redactor results used to authorize items" do
      query_redactor_results = T.let(Search::Queries::MemexProjectItemQueryRedactor::Results.new(
        authorized_repo_ids: [@private_repo.id],
        unauthorized_repo_ids: [],
        checked_for_spam: true
      ), Search::Queries::MemexProjectItemQueryRedactor::Results)

      redactor = MemexProjectItemRedactor.new(viewer: @member, items: [@private_issue_item], query_redactor_results:)

      assert_query_count(0, ignore_feature_flags: true) { redactor.items }
      refute_equal MemexProjectItem::REDACTED_ITEM_TYPE, redactor.items.first.content_type
      assert_dogstats_increment 1, MemexProjectItemRedactor::ZERO_ITEMS_CHECK_METRIC
      refute_dogstats_count MemexProjectItemRedactor::UNEXPECTED_ITEMS_CHECK_METRIC
    end

    test "query redactor results not used if memex_use_mwl_redactions disabled" do
      disable_feature_flag(:memex_use_mwl_redactions)

      query_redactor_results = T.let(Search::Queries::MemexProjectItemQueryRedactor::Results.new(
        authorized_repo_ids: [@private_repo.id],
        unauthorized_repo_ids: [],
        checked_for_spam: true
      ), Search::Queries::MemexProjectItemQueryRedactor::Results)

      redactor = MemexProjectItemRedactor.new(viewer: @member, items: [@private_issue_item], query_redactor_results:)

      assert_equal MemexProjectItem::REDACTED_ITEM_TYPE, redactor.items.first.content_type
      refute_dogstats_count MemexProjectItemRedactor::ZERO_ITEMS_CHECK_METRIC
      refute_dogstats_count MemexProjectItemRedactor::UNEXPECTED_ITEMS_CHECK_METRIC
    end

    test "query redactor results fall back to legacy item redaction if any are not authorized" do
      query_redactor_results = T.let(Search::Queries::MemexProjectItemQueryRedactor::Results.new(
        authorized_repo_ids: [],
        unauthorized_repo_ids: [],
        checked_for_spam: true
      ), Search::Queries::MemexProjectItemQueryRedactor::Results)

      redactor = MemexProjectItemRedactor.new(viewer: @member, items: [@private_issue_item], query_redactor_results:)

      assert_equal MemexProjectItem::REDACTED_ITEM_TYPE, redactor.items.first.content_type
      refute_dogstats_count MemexProjectItemRedactor::ZERO_ITEMS_CHECK_METRIC
      assert_dogstats_count 1, MemexProjectItemRedactor::UNEXPECTED_ITEMS_CHECK_METRIC
    end

    test "query redactor results fall back to legacy item redaction if any are not authorized, logging item and repository information" do
      private_repo_admin2 = create(:user)
      private_repo2 = create(:private_repository, owner: private_repo_admin2)
      private_issue2 = create(:issue, repository: private_repo2, user: private_repo_admin2)
      private_issue_item2 = create(:memex_project_item, memex_project: @memex, content: private_issue2)
      draft_item = @memex.build_draft_issue(creator: @admin, title: "draft 1")
      draft_item.save!

      query_redactor_results = T.let(Search::Queries::MemexProjectItemQueryRedactor::Results.new(
        authorized_repo_ids: [@repo.id, @private_repo.id],
        unauthorized_repo_ids: [],
        checked_for_spam: true
      ), Search::Queries::MemexProjectItemQueryRedactor::Results)

      redactor = MemexProjectItemRedactor.new(viewer: @member, items: [private_issue_item2, @issue_item, @private_issue_item, draft_item], query_redactor_results:)

      expected_summary_log = {
        :Body => MemexProjectItemRedactor::UNEXPECTED_ITEMS_CHECK_SUMMARY_LOG_MESSAGE,
        "code.namespace" => "MemexProjectItemRedactor",
        "code.function" => "result",
        "gh.memex.project.id" => private_issue_item2.memex_project_id,
        "gh.memex.items.auth.count" => 3,
        "gh.memex.items.draft.count" => 1,
        "gh.memex.items.unauth.count" => 1,
        "gh.memex.repo.auth.ids" => [@repo.id, @private_repo.id],
        "gh.memex.repo.unauth.ids" => [],
        "gh.user.id" => @member&.id
      }

      expected_log = {
        :Body => MemexProjectItemRedactor::UNEXPECTED_ITEMS_CHECK_LOG_MESSAGE,
        "code.namespace" => "MemexProjectItemRedactor",
        "code.function" => "result",
        "gh.memex.project.id" => private_issue_item2.memex_project_id,
        "gh.memex.item.id" => private_issue_item2.id,
        "gh.memex.item.content.type" => private_issue_item2.content_type,
        "gh.memex.item.repo.id" => private_issue_item2.repository_id,
        "gh.user.id" => @member.id
      }

      assert_logged(**expected_summary_log) do
        assert_logged(**expected_log) do
          assert_equal MemexProjectItem::REDACTED_ITEM_TYPE, redactor.items.first.content_type
        end
      end

      refute_dogstats_count MemexProjectItemRedactor::ZERO_ITEMS_CHECK_METRIC
      assert_dogstats_count 1, MemexProjectItemRedactor::UNEXPECTED_ITEMS_CHECK_METRIC
    end

    test "query redactor results used to authorize column values (linked PRs)" do
      query_redactor_results = T.let(Search::Queries::MemexProjectItemQueryRedactor::Results.new(
        authorized_repo_ids: [@repo.id, @repo2.id],
        unauthorized_repo_ids: [@private_repo.id],
        checked_for_spam: true
      ), Search::Queries::MemexProjectItemQueryRedactor::Results)

      prefill_result = MemexProjectItemPrefiller.new([@issue_item_with_4_linked_prs], columns: @memex.default_view.visible_columns).prefill
      redactor = MemexProjectItemRedactor.new(viewer: @admin, items: [@issue_item_with_4_linked_prs], columns: @memex.default_view.visible_columns, query_redactor_results:)

      assert_query_count(0, ignore_feature_flags: true) { redactor.redacted_issue_ids }
      assert_same_elements [@private_pull.issue.id], redactor.redacted_issue_ids

      assert_dogstats_increment 1, MemexProjectItemRedactor::ZERO_ISSUES_CHECK_METRIC
      refute_dogstats_count MemexProjectItemRedactor::NON_ZERO_ISSUES_CHECK_METRIC
    end

    test "query redactor results augmented by legacy issue redaction to omit unauthorized column values (linked PRs) if unknown" do
      query_redactor_results = T.let(Search::Queries::MemexProjectItemQueryRedactor::Results.new(
        authorized_repo_ids: [@repo.id, @repo2.id],
        unauthorized_repo_ids: [],
        checked_for_spam: true
      ), Search::Queries::MemexProjectItemQueryRedactor::Results)

      prefill_result = MemexProjectItemPrefiller.new([@issue_item_with_4_linked_prs], columns: @memex.default_view.visible_columns).prefill
      redactor = MemexProjectItemRedactor.new(viewer: @admin, items: [@issue_item_with_4_linked_prs], columns: @memex.default_view.visible_columns, query_redactor_results:)

      assert_same_elements [@private_pull.issue.id], redactor.redacted_issue_ids

      refute_dogstats_count MemexProjectItemRedactor::ZERO_ISSUES_CHECK_METRIC
      assert_dogstats_increment 1, MemexProjectItemRedactor::NON_ZERO_ISSUES_CHECK_METRIC
    end

    test "query redactor results augmented by legacy issue redaction to include authorized column values (linked PRs) if unknown" do
      query_redactor_results = T.let(Search::Queries::MemexProjectItemQueryRedactor::Results.new(
        authorized_repo_ids: [@repo.id],
        unauthorized_repo_ids: [@private_repo.id],
        checked_for_spam: true
      ), Search::Queries::MemexProjectItemQueryRedactor::Results)

      prefill_result = MemexProjectItemPrefiller.new([@issue_item_with_4_linked_prs], columns: @memex.default_view.visible_columns).prefill
      redactor = MemexProjectItemRedactor.new(viewer: @admin, items: [@issue_item_with_4_linked_prs], columns: @memex.default_view.visible_columns, query_redactor_results:)

      assert_same_elements [@private_pull.issue.id], redactor.redacted_issue_ids

      refute_dogstats_count MemexProjectItemRedactor::ZERO_ISSUES_CHECK_METRIC
      assert_dogstats_increment 1, MemexProjectItemRedactor::NON_ZERO_ISSUES_CHECK_METRIC
    end

    test "query redactor results not used to authorize column values (linked PRs) if memex_use_mwl_redactions disabled" do
      disable_feature_flag(:memex_use_mwl_redactions)

      query_redactor_results = T.let(Search::Queries::MemexProjectItemQueryRedactor::Results.new(
        authorized_repo_ids: [@repo.id, @repo2.id],
        unauthorized_repo_ids: [@private_repo.id],
        checked_for_spam: true
      ), Search::Queries::MemexProjectItemQueryRedactor::Results)

      prefill_result = MemexProjectItemPrefiller.new([@issue_item_with_4_linked_prs], columns: @memex.default_view.visible_columns).prefill
      redactor = MemexProjectItemRedactor.new(viewer: @admin, items: [@issue_item_with_4_linked_prs], columns: @memex.default_view.visible_columns, query_redactor_results:)

      assert_same_elements [@private_pull.issue.id], redactor.redacted_issue_ids

      refute_dogstats_count MemexProjectItemRedactor::ZERO_ISSUES_CHECK_METRIC
      refute_dogstats_count MemexProjectItemRedactor::NON_ZERO_ISSUES_CHECK_METRIC
    end

    if GitHub.spamminess_check_enabled?
      test "redacts an item created by spammy user" do
        redactor = MemexProjectItemRedactor.new(viewer: @member, items: [@spammy_item])
        result = assert_max_query_count_per_table({ issues: 2 }) { redactor.items }

        refute_equal @member, @spammy_item.creator
        refute_predicate @member, :site_admin?
        assert_empty result
      end

      test "does not redact an item created by spammy user when viewing as site admin" do
        redactor = MemexProjectItemRedactor.new(viewer: @site_admin, items: [@spammy_item])
        result = assert_max_query_count_per_table({ issues: 2 }) { redactor.items }

        assert_predicate @site_admin, :site_admin?
        assert_equal MemexProjectItem::ISSUE_TYPE, redactor.items.first.content_type
      end

      test "does not redact an item created by spammy user when viewing as spammy user" do
        redactor = MemexProjectItemRedactor.new(viewer: @spammy_user, items: [@spammy_item])
        result = assert_max_query_count_per_table({ issues: 2 }) { redactor.items }

        assert_equal @spammy_user, @spammy_item.creator
        assert_equal MemexProjectItem::ISSUE_TYPE, redactor.items.first.content_type
      end

      test "does not redact a linked pull request created by a spammy user when viewing as another org member" do
        prefill_result = MemexProjectItemPrefiller.new(
          [@issue_item_with_4_linked_prs],
          columns: @memex.default_view.visible_columns,
          read_denormalized_title: true,
          title_column: @memex.columns.find(&:title?)
        ).prefill

        redactor = MemexProjectItemRedactor.new(
          viewer: @member,
          items: [@issue_item_with_4_linked_prs],
          columns: @memex.default_view.visible_columns,
          prefilled_associations: prefill_result
        )

        # Note: to support denormalized values, Spammy linked PRs are not redacted
        expected = [@private_pull.issue.id]

        assert_max_query_count_per_table({ issues: 1 }) { redactor.redacted_issue_ids }
        assert_same_elements expected, redactor.redacted_issue_ids
      end

      test "does not redact a linked pull request created by a spammy user when viewing as a site admin" do
        prefill_result = MemexProjectItemPrefiller.new(
          [@issue_item_with_4_linked_prs],
          columns: @memex.default_view.visible_columns,
          read_denormalized_title: true,
          title_column: @memex.columns.find(&:title?)
        ).prefill

        redactor = MemexProjectItemRedactor.new(
          viewer: @site_admin,
          items: [@issue_item_with_4_linked_prs],
          columns: @memex.default_view.visible_columns,
          prefilled_associations: prefill_result
        )

        expected = [@private_pull.issue.id]

        assert_max_query_count_per_table({ issues: 1 }) { redactor.redacted_issue_ids }
        assert_same_elements expected, redactor.redacted_issue_ids
      end
    else
      test "does not redact an item created by spammy user" do
        redactor = MemexProjectItemRedactor.new(viewer: @member, items: [@spammy_item])
        result = assert_max_query_count_per_table({ issues: 2 }) { redactor.items }

        refute_equal @member, @spammy_item.creator
        refute_predicate @member, :site_admin?
        assert_equal MemexProjectItem::ISSUE_TYPE, redactor.items.first.content_type
      end

      test "does not redact an item created by spammy user when viewing as site admin" do
        redactor = MemexProjectItemRedactor.new(viewer: @site_admin, items: [@spammy_item])
        result = assert_max_query_count_per_table({ issues: 2 }) { redactor.items }

        assert_predicate @site_admin, :site_admin?
        assert_equal MemexProjectItem::ISSUE_TYPE, redactor.items.first.content_type
      end

      test "does not redact an item created by spammy user when viewing as spammy user" do
        redactor = MemexProjectItemRedactor.new(viewer: @spammy_user, items: [@spammy_item])
        result = assert_max_query_count_per_table({ issues: 2 }) { redactor.items }

        assert_equal @spammy_user, @spammy_item.creator
        assert_equal MemexProjectItem::ISSUE_TYPE, redactor.items.first.content_type
      end
    end
  end
end
