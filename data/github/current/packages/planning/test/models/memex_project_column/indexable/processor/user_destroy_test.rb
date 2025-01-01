# typed: true
# frozen_string_literal: true

require "test_helper"

class UserDestroyTest < GitHub::TestCase
  include HydroTestHelpers
  include MemexHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @actor = create(:verified_user, login: "actor")
    @user = create(:verified_user, login: "user")
    @assignee = create(:verified_user, login: "assignee")
    @reviewer = create(:verified_user, login: "reviewer1")
    @repo = create(:repository, owner: @user, from_example: :simple)
    @repo.add_member(@actor)
    @repo.add_member(@assignee)
    @repo.add_member(@reviewer)
    @project = create(:memex_project, owner: @actor, title: "my project")
    @issue = create(:issue, repository: @repo,  state: "open", assignee: @user)
    @issue_item = create(:memex_project_item, content: @issue, memex_project: @project)
    @pr_with_reviewer = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)
    create(:review_request, reviewer_id: @reviewer.id, pull_request_id: @pr_with_reviewer.id)
    @pr_item = create(:memex_project_item, content: @pr_with_reviewer, repository: @repo, memex_project: @project)
    @reviewers_field = @project.memex_project_columns.find(&:reviewers?).to_field
    @assignees_field = @project.memex_project_columns.find(&:assignees?).to_field
  end

  setup do
    setup_search
  end

  teardown do
    teardown_search
  end

  context "#subscriptions" do
    test "invoked on user destroy event" do
      assert_consumes(MemexProjectColumn::Indexable::Processor::UserDestroy, "github.v1.UserDestroy") do
        @user.async_destroy
      end
    end
  end

  context "#matching_elasticsearch_documents?" do
    test "returns true when there is at least one memex project item document in elasticsearch matching the issue" do
      populate_elasticsearch_index!([@issue_item])
      message = user_destroy_message(user: @user)
      assert MemexProjectColumn::Indexable::Processor::UserDestroy.new(message).matching_elasticsearch_documents?
    end

    test "returns true when the user destroyed is a reviewer on a project item" do
      populate_elasticsearch_index!([@pr_item])

      message = user_destroy_message(user: @reviewer)
      assert MemexProjectColumn::Indexable::Processor::UserDestroy.new(message).matching_elasticsearch_documents?
    end

    test "returns false when there are no memex project item documents in elasticsearch matching the issue" do
      other_repo = create(:repository, owner: @actor)
      other_project = create(:memex_project, owner: @actor, title: "my project")
      other_issue = create(:issue, repository: other_repo,  state: "open", assignee: @actor)
      other_project_item = create(:memex_project_item, content: other_issue, memex_project: other_project)
      populate_elasticsearch_index!([other_project_item])

      message = user_destroy_message(user: @user)
      refute MemexProjectColumn::Indexable::Processor::UserDestroy.new(message).matching_elasticsearch_documents?
    end
  end

  context "#canonical data fetching" do
    test "returns true if the user is deleted" do
      message = user_destroy_message(user: @user)
      @user.destroy!
      passes_through_canonical_data_gate = MemexProjectColumn::Indexable::Processor::UserDestroy.new(message).canonical_data_present?
      assert passes_through_canonical_data_gate
    end

    test "returns false when the user is not destroyed" do
      message = user_destroy_message(user: @user)

      passes_through_canonical_data_gate = MemexProjectColumn::Indexable::Processor::UserDestroy.new(message).canonical_data_present?
      refute passes_through_canonical_data_gate
    end
  end

  context "#update" do
    test "updates project item doc field_values when a user is destroyed" do
      item_in_another_project = create(:memex_project_item, content: @issue)
      populate_elasticsearch_index!([@issue_item, item_in_another_project])
      assert field(get_doc(@issue_item.id), @assignees_field.id)

      message = user_destroy_message(user: @user)
      response = MemexProjectColumn::Indexable::Processor::UserDestroy.new(message).update(es_client)

      assert_equal 2, T.must(response).to_hash[:updated]
      # The field should be removed entirely from the document since there was only 1 assignee
      refute field(get_doc(@issue_item.id), @assignees_field.id)
    end

    test "updates assignees field_value if the destroyed user is an assignee on a project item" do
      # Populate ES with an item with two assignees
      @issue.add_assignees([@assignee])
      populate_elasticsearch_index!([@issue_item])

      # Emit a user destroy message for one of the assignees
      message = user_destroy_message(user: @user)

      response = MemexProjectColumn::Indexable::Processor::UserDestroy.new(message).update(es_client)
      index.refresh

      # Get the assignees field value for @issue_item
      doc = get_doc(@issue_item.id)
      assignees_value = field_value(doc, @assignees_field)

      # Assert that the destroyed user is no longer an assignee but the other assignee remains
      refute assignees_value.find { _1["login"] == @user.login }
      assert assignees_value.find { _1["login"] == @assignee.login }
    end

    test "updates reviewers field_value if the destroyed user is a reviewer on a project item" do
      # Create two pr memex items with different reviewers
      reviewer2 = create(:verified_user, login: "reviewer2")
      @repo.add_member(reviewer2, action: :write)
      create(:review_request, reviewer_id: reviewer2.id, pull_request_id: @pr_with_reviewer.id)
      populate_elasticsearch_index!([@pr_item])

      # Emit a UserDestroy hydro message
      message = user_destroy_message(user: @reviewer)

      response = MemexProjectColumn::Indexable::Processor::UserDestroy.new(message).update(es_client)
      index.refresh

      # Get the reviewers field value for @pr_item
      doc = get_doc(@pr_item.id)
      reviewers_value = field_value(doc, @reviewers_field)

      # Assert that reviewer1 no longer is a reviewer, but reviewer 2 remains
      refute reviewers_value.find { _1["actor_slug"] == @reviewer.login }
      assert reviewers_value.find { _1["actor_slug"] == reviewer2.login }
    end

    test "no-ops when values are unchanged" do
      # Remove @reviewer as a reviewer on the pr
      @pr_with_reviewer.review_requests.destroy_all
      populate_elasticsearch_index!([@pr_item])

      # Emit a UserDestroy hydro message
      @pr_item.clear_column_value(@reviewrs_field, @user)
      message = user_destroy_message(user: @reviewer)

      response = MemexProjectColumn::Indexable::Processor::UserDestroy.new(message).update(es_client)
      index.refresh

      # Assert no records were updated
      assert_equal 0, T.must(response).to_hash[:updated]
    end
  end

  test "provides correct project ids for resyncing on failure", es_8_only: true do
    issue = create(:issue, repository: @repo, assignee: @user)
    item_in_another_project = create(:memex_project_item, content: issue)
    populate_elasticsearch_index!([@issue_item, item_in_another_project])

    message = user_destroy_message(user: @user)
    processor = MemexProjectColumn::Indexable::Processor::UserDestroy.new(message)
    assert_equal [@project.id, item_in_another_project.memex_project_id].sort, processor.project_ids_to_resync_on_failure.sort
  end

  private

  def user_destroy_message(user:)
    build_message(
      {
        actor: Hydro::EntitySerializer.user(@actor),
        user: Hydro::EntitySerializer.user(user)
      },
      schema: "hydro.schemas.github.v1.UserDestroy"
    )
  end
end
