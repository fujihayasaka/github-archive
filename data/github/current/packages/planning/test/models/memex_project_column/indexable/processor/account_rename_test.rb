# typed: true
# frozen_string_literal: true

require "test_helper"

class AccountRenameProcessorTest < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @actor = create(:verified_user)
    @user = create(:verified_user)
    @repo = create(:repository, owner: @user)
    @repo.add_member(@actor)
    @project = create(:memex_project, owner: @actor, title: "test project")
    @issue = create(:issue, repository: @repo,  state: "open", assignee: @user)
  end

  setup do
    setup_search
  end

  context "#subscriptions" do
    test "invoked on account rename event" do
      assert_consumes(MemexProjectColumn::Indexable::Processor::AccountRename, "github.v1.AccountRename") do
        @user.rename!("account-rename-test")
      end
    end
  end

  context "#matching_elasticsearch_documents?" do
    test "returns true when there is at least one memex project item document in elasticsearch matching the issue" do
      project_item = create(:memex_project_item, content: @issue, memex_project: @project)
      populate_elasticsearch_index!([project_item])

      message = account_rename_message(@user, "foo")

      assert MemexProjectColumn::Indexable::Processor::AccountRename.new(message).matching_elasticsearch_documents?
    end


    test "returns false when there are no memex project item documents in elasticsearch matching the issue" do
      project_item = create(:memex_project_item, content: @issue, memex_project: @project)
      populate_elasticsearch_index!([project_item])

      message = account_rename_message(@actor, "foo")

      refute MemexProjectColumn::Indexable::Processor::AccountRename.new(message).matching_elasticsearch_documents?
    end
  end

  context "#canonical data fetching" do
    test "returns true when the model is present" do
      message = account_rename_message(@user, @user.login, "new_user_login")

      passes_through_canonical_data_gate = MemexProjectColumn::Indexable::Processor::AccountRename.new(message).canonical_data_present?
      assert passes_through_canonical_data_gate
    end

    test "returns false when the model is not present" do
      message = account_rename_message(@user, @user.login, "new_user_login")
      @user.delete
      passes_through_canonical_data_gate = MemexProjectColumn::Indexable::Processor::AccountRename.new(message).canonical_data_present?
      refute passes_through_canonical_data_gate
    end
  end

  context "#update" do
    test "updates project item doc field_values across projects when an account is renamed" do
      project_item = create(:memex_project_item, content: @issue, memex_project: @project)
      issue = create(:issue, repository: @repo, assignee: @user)
      item_in_another_project = create(:memex_project_item, content: issue)
      populate_elasticsearch_index!([project_item, item_in_another_project])

      message = account_rename_message(@user, "new_login")

      response = MemexProjectColumn::Indexable::Processor::AccountRename.new(message).update(es_client)
      @index.refresh

      assert_equal 2, T.must(response).to_hash[:updated]
    end

    test "update assignees field_value if the renamed account is assigned to a project item" do
      # arrange
      repo = create(:repository, owner: @actor)
      repo.add_member(@user)
      issue = create(:issue, repository: repo, assignee: @user)
      project_item = create(:memex_project_item, content: @issue, memex_project: @project)
      item_in_another_project = create(:memex_project_item, content: issue)
      populate_elasticsearch_index!([project_item, item_in_another_project])

      previous_login = @user.login
      new_login = "account-rename-test"

      # act
      @user.rename!(new_login)
      message = account_rename_message(@user, new_login, previous_login)

      response = MemexProjectColumn::Indexable::Processor::AccountRename.new(message).update(es_client)
      @index.refresh

      # assert
      results = @index.search_all({ "query": { "match_all": {} } })
      assignee_logins = results.dig("hits", "hits")
        .map { |result_item| result_item["_source"] }
        .map { _1["field_values"] }.flatten
        .select { _1["field_type"] == "assignees" }
        .map { _1["assignees_value"] }.flatten
        .map { _1["login"] }

      assert_equal 2, assignee_logins.count { _1 == new_login }

      assert_equal 2, T.must(response).to_hash[:updated]
    end

    test "update reviewers field_value if the renamed account a reviewer to a project item" do
      # arrange
      repo = create(:repository, owner: @actor)
      repo.add_member(@user)

      pr_with_reviewer = create(:pull_request, :disable_disk_access, repository: repo)
      review = create(:pull_request_review, pull_request: pr_with_reviewer, user: @user)
      project_item = create(:memex_project_item, content: pr_with_reviewer)

      pr_no_reviewer = create(:pull_request, :disable_disk_access)
      another_project_item = create(:memex_project_item, content: pr_no_reviewer)
      populate_elasticsearch_index!([project_item, another_project_item])

      previous_login = @user.login
      new_login = "account-rename-test"

      # act
      @user.rename!(new_login)
      message = account_rename_message(@user, new_login, previous_login)

      response = MemexProjectColumn::Indexable::Processor::AccountRename.new(message).update(es_client)
      @index.refresh

      # assert
      results = @index.search_all({ "query": { "match_all": {} } })
      reviewer_logins = results.dig("hits", "hits")
        .map { |result_item| result_item["_source"] }
        .map { _1["field_values"] }.flatten
        .select { _1["field_type"] == "reviewers" }
        .map { _1["reviewers_value"] }.flatten
        .map { _1["actor_slug"] }

      assert_equal 1, reviewer_logins.count { _1 == new_login }

      assert_equal 1, T.must(response).to_hash[:updated]
    end

    test "update repository field_value if the renamed account is the owner of a repo referenced by a project item" do
      # arrange
      repo = create(:repository, owner: @user)
      repo_name = repo.name
      issue = create(:issue, repository: repo)
      project_item = create(:memex_project_item, content: issue)

      another_issue = create(:issue)
      another_project_item = create(:memex_project_item, content: another_issue)

      populate_elasticsearch_index!([project_item, another_project_item])

      previous_login = @user.login
      new_login = "account-rename-test"

      # act
      @user.rename!(new_login)
      message = account_rename_message(@user, new_login, previous_login)

      response = MemexProjectColumn::Indexable::Processor::AccountRename.new(message).update(es_client)
      @index.refresh

      # assert
      results = @index.search_all({ "query": { "match_all": {} } })

      repository_full_name = results.dig("hits", "hits")
        .map { _1["_source"] }
        .map { _1["field_values"] }.flatten
        .select { _1["field_type"] == "repository" }
        .map { _1["repository_value"] }
        .select { _1["owner_id"] == @user.id }
        .map { _1["full_name"] }

      assert_equal repository_full_name[0], "#{new_login}/#{repo_name}"
      assert_equal 1, T.must(response).to_hash[:updated]
    end

    test "provides correct project ids for resyncing on failure", es_8_only: true do
      project_item = create(:memex_project_item, content: @issue, memex_project: @project)
      issue = create(:issue, repository: @repo, assignee: @user)
      item_in_another_project = create(:memex_project_item, content: issue)
      populate_elasticsearch_index!([project_item, item_in_another_project])

      message = account_rename_message(@user, "foo")
      processor = MemexProjectColumn::Indexable::Processor::AccountRename.new(message)
      assert_equal [@project.id, item_in_another_project.memex_project_id].sort, processor.project_ids_to_resync_on_failure.sort
    end

    test "provides correct updated models", es_8_only: true do
      message = account_rename_message(@user, "foo")
      processor = MemexProjectColumn::Indexable::Processor::AccountRename.new(message)
      assert_equal [@user], processor.updated_models
    end
  end

  private

  def account_rename_message(user = @actor, current_login = user.login, previous_login = user.login)
    build_message(
      {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(user),
        account: Hydro::EntitySerializer.user(user),
        previous_login: previous_login,
        current_login: current_login,
      },
      schema: "hydro.schemas.github.v1.AccountRename"
    )
  end
end
