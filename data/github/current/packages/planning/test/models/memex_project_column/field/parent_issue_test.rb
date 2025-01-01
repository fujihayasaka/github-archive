# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnParentIssueTest < GitHub::TestCase
  include MemexHelpers

  fixtures do
    @admin = create(:verified_user)
    @org = create(:organization, admin: @admin)
    @repo = create(:private_repository, owner: @org)

    @child = create(:issue, repository: @repo)
    @parent = create(:issue, repository: @repo, title: "c")
    @parent.add_sub_issue!(@child, @admin.id)

    @pull_request = create(
      :pull_request,
      :disable_disk_access,
      repository: @repo,
      user: @admin,
      head_ref: "ref-#{SecureRandom.hex(6)}"
    )

    @memex = create(:memex_project, owner: @org)
    @item = create(:memex_project_item, content: @child, memex_project: @memex)
    @pr_item = create(:memex_project_item, content: @pull_request, memex_project: @memex)
    @draft_issue_item = @memex.build_draft_issue(creator: @admin, title: "An idea").tap(&:save!)

    @parent_issue_field = @item.memex_project.columns.find(&:parent_issue?)&.to_field
  end

  setup do
    setup_search
  end

  teardown_once do
    teardown_search
  end

  context ".elasticsearch_mapping" do
    test "returns the correct object configuration" do
      assert_equal(
        {
          dynamic: "strict",
          properties: {
            id: { type: "long" },
            nwo_reference: { type: "text", fields: { keyword: { type: "keyword" } }, copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS },
            title: { type: "text", fields: { keyword: { type: "keyword" } } },
            owner_id: { type: "long" },
          }
        },
        @parent_issue_field.class.elasticsearch_mapping.to_hash
      )
    end
  end

  context "#preload_elasticsearch_document_data" do
    test "preloads parent issue data" do
      more_items = 3.times.map do |_i|
        org2 = create(:organization, admin: @admin)
        repo2 = create(:private_repository, owner: org2)
        child2 = create(:issue, repository: repo2)
        parent2 = create(:issue, repository: repo2)
        parent2.add_sub_issue!(child2, @admin.id)
        create(:memex_project_item, content: child2, memex_project: @memex)
      end
      assert_query_count_per_table({
        # First for the issue items, then for their parents
        issues: 2,
        # since getting repositories for parents uses the already filled repositories for the children as available_records,
        # only one query is made to repositories
        repositories: 1,
        # once for organizations for the repositories
        users: 1,
      }) do
        @parent_issue_field.preload_elasticsearch_document_data([@item] + more_items)
      end
      assert_no_queries { @parent_issue_field.elasticsearch_document(@item) }
    end

    test "preloads parent issue data even if some content has been deleted" do
      @item.expects(:content)
        .times(3)
        .returns(@item.content)
        .then
        .returns(nil)

      assert_nothing_raised do
        @parent_issue_field.preload_elasticsearch_document_data([@item])
      end
    end
  end

  context "#elasticsearch_document" do
    test "returns a fragment containing a parent issue for an issue item" do
      assert_equal(
        {
          id: @parent.id,
          nwo_reference: @parent.name_with_display_owner_reference,
          title: @parent.title,
          owner_id: @parent.owner.id,
        },
        @parent_issue_field.elasticsearch_document(@item).to_hash
      )
    end

    test "returns nil for a draft issue" do
      assert_nil @parent_issue_field.elasticsearch_document(@draft_issue_item)
    end

    test "returns nil for a pull request" do
      assert_nil @parent_issue_field.elasticsearch_document(@pr_item)
    end
  end

  context "#seed_elasticsearch_document" do
    test "generates arbitrary parent issue numbers" do
      context = Elastomer::Interfaces::Document::MemexProjectItem::SeedContext.new(require_non_nil_value: true)
      assert @parent_issue_field.seed_elasticsearch_document(context)
    end
  end

  context "#query_fragment" do
    test "returns the expected results querying by a parent issue", es_8_only: true do
      context = Search::Memex::Context.new(memex_project: @memex, viewer: @admin)
      child2 = create(:issue, repository: @repo)
      parent2 = create(:issue, repository: @repo)
      parent2.add_sub_issue!(child2, @admin.id)
      child2_item = create(:memex_project_item, content: child2, memex_project: @memex)
      populate_elasticsearch_index!([@item, child2_item])
      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @admin,
        query: "#{@parent_issue_field.name_slug}:#{@parent.name_with_display_owner_reference}",
      )
      response = query.execute
      assert_equal 1, response.results.length
      assert_equal @item.id, response.results.first.dig("_source", "database_id")
    end
  end

  context "#sort_by parent" do
    test "sort by parent title", es_8_only: true do
      repo2 = create(:private_repository, owner: @org)
      parent2 = create(:issue, repository: repo2, title: "a")
      child2 = create(:issue, repository: repo2)
      repo3 = create(:private_repository, owner: @org)
      parent3 = create(:issue, repository: repo3, title: "b")
      child3 = create(:issue, repository: repo3)
      parent2.add_sub_issue!(child2, @admin.id)
      parent3.add_sub_issue!(child3, @admin.id)
      child2_item = create(:memex_project_item, content: child2, memex_project: @memex)
      child3_item = create(:memex_project_item, content: child3, memex_project: @memex)

      populate_elasticsearch_index!([@item, child2_item, child3_item])
      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @admin,
        sort: [@parent_issue_field.sort_fragment(direction: "asc")],
      )
      response = query.execute

      assert_equal 3, response.results.length
      # Should sort by repos with names "a", "b", then "c"
      assert_equal child2_item.id.to_s, response.results[0]["_id"]
      assert_equal child3_item.id.to_s, response.results[1]["_id"]
      assert_equal @item.id.to_s, response.results[2]["_id"]
    end
  end
end
