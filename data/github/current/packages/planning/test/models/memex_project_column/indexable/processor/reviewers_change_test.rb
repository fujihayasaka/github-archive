# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumn::Indexable::Processor::ReviewersChangeTest < GitHub::TestCase
  include HydroTestHelpers
  include MemexHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @actor = create(:user, login: "actor")
    @owner = create(:user, login: "owner")
    @org = create(:organization, login: "org")
    @repo = create(:repository, owner: @org, name: "repo", from_example: :simple)
    @repo.add_member(@actor, action: :write)
    @repo.add_member(@owner, action: :write)
    @pull_request = create(:pull_request, :with_mergeable_head, repository: @repo, user: @actor)
    @reviewer = create(:verified_user, login: "reviewer")
    @repo.add_member(@reviewer, action: :write)
    @project_item = create(:memex_project_item, content: @pull_request, repository_id: @repo.id)
    @reviewers_field = @project_item.memex_project.columns.find(&:reviewers?).to_field
    @team = create(:team, organization: @org, privacy: :closed, name: "team")
    @team.add_repository(@repo, :push)
  end

  setup do
    setup_search
    @index = Elastomer::Indexes::MemexProjectItems.new
  end

  teardown do
    teardown_search
  end

  context "#subscriptions" do
    test "invoked in response to a pull request review request message" do
      assert_consumes(MemexProjectColumn::Indexable::Processor::ReviewersChange, "github.v1.PullRequestReviewRequest") do
        @pull_request.review_requests.create(reviewer: @reviewer)
      end
    end

    test "invoked when a reviewer is added by submitting a review comment" do
      submitted_comment_review = create(:pull_request_review, :submitted, pull_request: @pull_request, user: @reviewer)
      review_comment = create(:pull_request_review_comment,
        :submitted,
        pull_request: @pull_request,
        user: @reviewer,
        pull_request_review: submitted_comment_review,
      )

      reset_hydro

      assert_consumes(MemexProjectColumn::Indexable::Processor::ReviewersChange, "github.v1.PullRequestReviewSubmit") do
        submitted_comment_review.comment!(review_comment)
      end
    end

    test "invoked when a reviewer is added by approving a pull request" do
      approving_review = @pull_request.reviews.create!(user: @reviewer, head_sha: @pull_request.head_sha)
      reset_hydro

      assert_consumes(MemexProjectColumn::Indexable::Processor::ReviewersChange, "github.v1.PullRequestReviewSubmit") do
        approving_review.approve!
      end
    end

    test "invoked when a reviewer is added by requesting changes to a pull request" do
      changes_requested_review = @pull_request.reviews.create!(user: @reviewer, head_sha: @pull_request.head_sha, body: "please make changes")
      reset_hydro

      assert_consumes(MemexProjectColumn::Indexable::Processor::ReviewersChange, "github.v1.PullRequestReviewSubmit") do
        changes_requested_review.request_changes!
      end
    end
  end

  context "#dependent_mysql_replication_cluster" do
    test "returns the PullRequests cluster" do
      message = column_update_message(pull_request: @pull_request)
      processor = MemexProjectColumn::Indexable::Processor::ReviewersChange.new(message)
      assert_equal PullRequest.cluster_name, processor.dependent_mysql_replication_cluster
    end
  end

  context "#matching_elasticsearch_documents?" do
    test "returns true when at least one item matching the pull request is found in elasticsearch" do
      populate_elasticsearch_index!([@project_item])
      message = column_update_message(pull_request: @pull_request)
      matching_elasticsearch_documents = MemexProjectColumn::Indexable::Processor::ReviewersChange.new(message).matching_elasticsearch_documents?
      assert matching_elasticsearch_documents
    end

    test "returns false when no items are returned from elasticsearch" do
      other_pull_request = create(:pull_request, :disable_disk_access, repository: @repo, user: @actor, head_ref: "ref-#{SecureRandom.hex(6)}")
      other_pr_item = create(:memex_project_item, content: other_pull_request, memex_project: @project_item.memex_project)
      message = column_update_message(pull_request: other_pull_request)
      matching_elasticsearch_documents = MemexProjectColumn::Indexable::Processor::ReviewersChange.new(message).matching_elasticsearch_documents?
      refute matching_elasticsearch_documents
    end
  end

  context "#canonical_data_present?" do
    test "returns true when pull request is present" do
      message = column_update_message(pull_request: @pull_request)
      passes_through_canonical_data_gate = MemexProjectColumn::Indexable::Processor::ReviewersChange.new(message).canonical_data_present?
      assert passes_through_canonical_data_gate
    end

    test "returns false when the pull request is not present" do
      message = column_update_message(pull_request: @pull_request)
      @pull_request.delete
      passes_through_canonical_data_gate = MemexProjectColumn::Indexable::Processor::ReviewersChange.new(message).canonical_data_present?
      refute passes_through_canonical_data_gate
    end
  end

  context "#project_ids_to_resync_on_failure" do
    test "provides correct project ids for resyncing on failure" do
      create(:review_request, reviewer_id: @reviewer.id, pull_request_id: @pull_request.id)
      # Create a project and pr item that should not resync on failure
      project_2 = create(:memex_project)
      pull_request_2 = create(:pull_request, :disable_disk_access, repository: @repo, user: @actor, head_ref: "ref-#{SecureRandom.hex(6)}")
      pr_item_in_another_project = create(:memex_project_item,  memex_project: project_2, content: pull_request_2)
      create(:review_request, reviewer_id: @reviewer.id, pull_request_id: pull_request_2.id)

      # Add two prs to elasticsearch: one that should resync on failure, and one that should not
      populate_elasticsearch_index!([@project_item, pr_item_in_another_project])
      message = column_update_message(pull_request: @pull_request)
      processor = MemexProjectColumn::Indexable::Processor::ReviewersChange.new(message)

      # Check that only the project containing the updated pr is returned
      assert_equal [@project_item.memex_project_id], processor.project_ids_to_resync_on_failure
    end
  end

  context "#update" do
    test "updates project item when a user is added to the reviewers list" do
      populate_elasticsearch_index!([@project_item])

      create(:review_request, reviewer_id: @reviewer.id, pull_request_id: @pull_request.id)
      message = column_update_message(reviewer: @reviewer)
      processor = MemexProjectColumn::Indexable::Processor::ReviewersChange.new(message)
      response = processor.update(es_client)

      assert_equal 1, response.items.size
      assert_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Updated, response.items.first&.update&.result
      doc = get_doc(@project_item.id)
      assert field_value(doc, @reviewers_field).find { _1["actor_id"] == @reviewer.id }
    end

    test "updates project item when a team is added to the reviewers list" do
      populate_elasticsearch_index!([@project_item])
      @pull_request.review_requests.create!(reviewer: @team)
      message = column_update_message(reviewer: @team)
      processor = MemexProjectColumn::Indexable::Processor::ReviewersChange.new(message)
      response = processor.update(es_client)

      assert_equal 1, response.items.size
      assert_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Updated, response.items.first&.update&.result
      doc = get_doc(@project_item.id)
      assert field_value(doc, @reviewers_field).find { _1["actor_id"] == @team.id }
    end

    test "updates project item when a user has reviewed the pull request" do
      populate_elasticsearch_index!([@project_item])

      review = create(:pull_request_review, :approved, pull_request: @pull_request, user: @reviewer)
      @project_item.content.reload
      message = review_submit_message(reviewer: @reviewer, review:)
      processor = MemexProjectColumn::Indexable::Processor::ReviewersChange.new(message)
      response = processor.update(es_client)

      assert_equal response.items.size, 1
      assert_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Updated, response.items.first&.update&.result

      doc = get_doc(@project_item.id)
      expected = @reviewers_field.elasticsearch_document(@project_item).map(&:to_hash)
      actual = field_value(doc, @reviewers_field).map(&:symbolize_keys)
      assert_equal expected, actual
    end

    test "noops when the updated_reviewers_list contains the same reviewers" do
      @pull_request.review_requests.create!(reviewer: @reviewer)
      @pull_request.review_requests.create!(reviewer: @team)
      populate_elasticsearch_index!([@project_item])

      message = column_update_message(reviewer: @reviewer)
      processor = MemexProjectColumn::Indexable::Processor::ReviewersChange.new(message)
      response = processor.update(es_client)

      assert_equal 1, response.items.size
      assert_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Noop, response.items.first&.update&.result
    end

    test "removes field from field_values when last reviewer is removed" do
      req = @pull_request.review_requests.create!(reviewer: @reviewer)
      populate_elasticsearch_index!([@project_item])
      req.destroy!

      message = column_update_message(reviewer: @reviewer)
      processor = MemexProjectColumn::Indexable::Processor::ReviewersChange.new(message)
      response = processor.update(es_client)

      assert_equal 1, response.items.size
      assert_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Updated, response.items.first&.update&.result
      doc = get_doc(@project_item.id)
      assert_nil field(doc, @reviewers_field.id)
    end
  end

  def column_update_message(pull_request: @pull_request, reviewer: @reviewer, action: :REQUESTED)
    serialized_user = reviewer.is_a?(User) ? Hydro::EntitySerializer.user(reviewer) : nil
    serialized_team = reviewer.is_a?(Team) ? Hydro::EntitySerializer.team(reviewer) : nil
    build_message(
      {
        pull_request: Hydro::EntitySerializer.pull_request(pull_request),
        actor: Hydro::EntitySerializer.user(@actor),
        repository: Hydro::EntitySerializer.repository(@repo),
        action: action,
        subject_user: serialized_user,
        subject_team: serialized_team
      },
      schema: "github.v1.PullRequestReviewRequest",
    )
  end

  def review_submit_message(pull_request: @pull_request, reviewer: @reviewer, review: nil)
    serialized_user = Hydro::EntitySerializer.user(reviewer)
    build_message(
      {
        actor: serialized_user,
        repository: Hydro::EntitySerializer.repository(@repo),
        pull_request: Hydro::EntitySerializer.pull_request(pull_request),
        pull_request_review: Hydro::EntitySerializer.pull_request_review(review),
        repository_owner: Hydro::EntitySerializer.user(@repo.owner),
        feature_flags: nil,
        issue: Hydro::EntitySerializer.issue(pull_request.issue),
        request_context: Hydro::EntitySerializer.request_context(@reviewer),
      },
      schema: "github.v1.PullRequestReviewSubmit",
    )
  end
end
