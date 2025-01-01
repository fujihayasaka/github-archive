# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnLinkedPullRequestsTest < GitHub::TestCase
  fixtures do
    @admin = create(:verified_user)
    @org = create(:organization, admin: @admin)
    @repo = create(:private_repository, owner: @org)
    @pull_request = create(
      :pull_request,
      :disable_disk_access,
      repository: @repo,
      user: @admin,
      head_ref: "ref-#{SecureRandom.hex(6)}"
    )

    @issue = create(:issue, repository: @repo, user: @admin)
    create(:close_issue_reference, issue: @issue, pull_request: @pull_request)

    @memex = create(:memex_project, owner: @org)
    @item = create(:memex_project_item, content: @issue, memex_project: @memex)
    @pr_item = create(:memex_project_item, content: @pull_request, memex_project: @memex)
    @draft_issue_item = @memex.build_draft_issue(creator: T.must(@issue).user, title: "An idea").tap(&:save!)

    @linked_pull_requests_field = @item.memex_project.columns.find(&:linked_pull_requests?)&.to_field
  end

  context ".elasticsearch_mapping" do
    test "returns the correct object configuration" do
      assert_equal(
        {
          dynamic: "strict",
          properties: {
            number: { type: "text", fields: { keyword: { type: "keyword" } }, copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS },
            id: { type: "long" },
            repository_id: { type: "long" }
          }
        },
        @linked_pull_requests_field.class.elasticsearch_mapping.to_hash
      )
    end
  end

  context "#preload_elasticsearch_document_data" do
    test "preloads linked pull requests data" do
      @linked_pull_requests_field.preload_elasticsearch_document_data([@item])
      assert_no_queries { @linked_pull_requests_field.elasticsearch_document(@item) }
    end

    test "preloads linked pull requests data even if some content has been deleted" do
      @item.expects(:content)
        .times(3)
        .returns(@item.content)
        .then
        .returns(nil)
      assert_nothing_raised do
        @linked_pull_requests_field.preload_elasticsearch_document_data([@item])
      end
    end
  end

  context "#elasticsearch_document" do
    test "returns a fragment containing an array of linked pull request objects for an issue item" do
      linked_prs = @issue.close_issue_references.map do |ref|
        {
          number: ref.pull_request.number.to_s,
          id: ref.pull_request_id,
          repository_id: ref.pull_request.repository_id
        }
      end
      refute_empty linked_prs

      assert_equal(
        linked_prs,
        @linked_pull_requests_field.elasticsearch_document(@item).map { |l| l.to_hash }
      )
    end

    test "returns nil for a draft issue" do
      assert_nil @linked_pull_requests_field.elasticsearch_document(@draft_issue_item)
    end

    test "returns nil for a pull request" do
      assert_nil @linked_pull_requests_field.elasticsearch_document(@pr_item)
    end
  end

  context "#seed_elasticsearch_document" do
    test "generates arbitrary linked pull request numbers" do
      context = Elastomer::Interfaces::Document::MemexProjectItem::SeedContext.new(require_non_nil_value: true)
      refute_empty @linked_pull_requests_field.seed_elasticsearch_document(context)
    end
  end
end
