# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesAuditProjectQueryTest < GitHub::TestCase
  include AuditLogHelpers

  if GitHub.enterprise?
    fixtures do
      @user = create(:user, login: "usethis", plan: "medium", email: "user@fake.org")
      @org = create(:organization)
      @org.add_member(@user)

      @repo = create(:repository, owner: @org)

      @repo_project = create(:project, owner: @repo, name: "Project 1")
      @repo_project2 = create(:project, owner: @repo, name: "Project 2")
    end

    setup do
      @created_time = Time.at(1411413154).in_time_zone("Pacific Time (US & Canada)") # 2014-09-22 12:12:34 -0700
      @updated_time = Time.at(1411413266).in_time_zone("Pacific Time (US & Canada)") # 2014-09-22 12:14:26 -0700
      @deleted_time = Time.at(1431413522).in_time_zone("Pacific Time (US & Canada)") # 2015-05-11 23:52:02 -0700

      Timecop.freeze(@deleted_time) do
        @deleted_time_query = build_projects_query(@repo_project, latest_allowed_entry_time: @deleted_time.to_s)
      end unless defined? @deleted_time_query

      Timecop.freeze(@updated_time) do
        @updated_time_query = build_projects_query(@repo_project, latest_allowed_entry_time: @updated_time.to_s)
      end unless defined? @updated_time_query

      Timecop.freeze(@created_time) do
        @created_time_query = build_projects_query(@repo_project, latest_allowed_entry_time: @created_time.to_s)
      end unless defined? @created_time_query
    end

    context "creating the query" do
      test "raises an exception if no project context" do
        assert_raises KeyError do
          Search::Queries::Audit::ProjectQuery.new
        end
      end

      test "with project context" do
        query = build_projects_query(@repo_project)
        assert_equal query.project, @repo_project
      end
    end

    context "filters" do
      test "filters by project" do
        with_es_refresh do
          log action: "project.create", data: { project_id: @repo_project.id }
          log action: "project.create", data: { project_id: @repo_project2.id }
        end

        query = build_projects_query(@repo_project2)
        response = query.execute

        assert_equal 1, response.total
        assert_actions ["project.create"], response
        assert_equal @repo_project2.id, response.results.first["data"]["project_id"]
      end

      test "project actions" do
        actions = %w(
          project.create
          project.update
          project.delete
          project.rename
          project.link
          project.unlink
        )

        with_es_refresh do
          actions.each do |action|
            log action: action, data: { project_id: @repo_project.id }
          end
        end

        query = build_projects_query(@repo_project)
        response = query.execute

        assert_equal 5, response.total
        # rename is filtered out so don't expect that one
        assert_actions actions - ["project.rename"], response
      end

      test "project column actions" do
        actions = %w(
          project_column.create
          project_column.update
          project_column.move
          project_column.delete
        )

        with_es_refresh do
          actions.each do |action|
            log action: action, data: { project_id: @repo_project.id }
          end
        end

        query = build_projects_query(@repo_project)
        response = query.execute

        assert_equal 4, response.total
        assert_actions actions, response
      end

      test "card actions" do
        actions = %w(
          project_card.create
          project_card.update
          project_card.delete
          project_card.convert
          project_card.move
          project_card.archive
          project_card.restore
        )

        with_es_refresh do
          actions.each do |action|
            log action: action, data: { project_id: @repo_project.id }
          end
        end

        query = build_projects_query(@repo_project)
        response = query.execute

        assert_equal 6, response.total
        # move without a changes hash is filtered out so don't expect that one
        assert_actions actions - ["project_card.move"], response
      end

      test "filters out card moves that are inter-column" do
        with_es_refresh do
          log action: "project_card.move", data: {
            project_id: @repo_project.id,
            "changes": {
              old_column_id: 1,
              column_id: 2,
            },
          }
          log action: "project_card.move", data: { project_id: @repo_project.id }
        end

        query = build_projects_query(@repo_project)

        response = query.execute

        assert_equal 1, response.total
        assert_actions ["project_card.move"], response
        refute_nil response.results.first["data"]["changes"]
      end

      test "project workflow actions" do
        actions = %w(
          project_workflow.create
          project_workflow.update
          project_workflow.delete
        )

        with_es_refresh do
          actions.each do |action|
            log action: action, data: { project_id: @repo_project.id }
          end
        end

        query = build_projects_query(@repo_project)
        response = query.execute

        assert_equal 3, response.total
        assert_actions actions, response
      end

      test "memex project actions" do
        classic_project = create(:project, owner: @user)
        memex_project = create(:memex_project, id: classic_project.id, owner: @user)

        assert_equal classic_project.id, memex_project.id

        with_es_refresh do
          log action: "project.create", data: {
            project_id: memex_project.id,
            project_kind: "MemexProject",
          }
        end

        query = build_projects_query(classic_project)
        response = query.execute

        assert_equal 1, response.total
        assert_actions ["project.create"], response
        assert_nil response.results.first["data"]["project_kind"]
      end
    end

    context "sort order" do
      test "activity sorted by timestamp and rank" do

        Timecop.freeze(@created_time) do
          with_es_refresh do
            log action: "project_card.create", created_at: @created_time, data: { project_id: @repo_project.id, rank: 3 }
            log action: "project_column.create", created_at: @created_time, data: { project_id: @repo_project.id, rank: 2 }
            log action: "project.create", created_at: @created_time, data: { project_id: @repo_project.id, rank: 1 }
            log action: "project_workflow.create", created_at: @created_time, data: { project_id: @repo_project.id, rank: 4 }

            log action: "project_card.update", created_at: @updated_time, data: { project_id: @repo_project.id, rank: 3 }
            log action: "project_column.update", created_at: @updated_time, data: { project_id: @repo_project.id, rank: 2 }
            log action: "project_workflow.update", created_at: @updated_time, data: { project_id: @repo_project.id, rank: 4 }
            log action: "project.update", created_at: @updated_time, data: { project_id: @repo_project.id, rank: 1 }
          end
        end

        Timecop.freeze(@updated_time) do
          query = build_projects_query(@repo_project)
          response = query.execute

          assert_equal 8, response.total
          actions = response.results.collect { |h| h["action"] }
          assert_equal ["project_workflow.update", "project_card.update", "project_column.update", "project.update", "project_workflow.create", "project_card.create", "project_column.create", "project.create"], actions
        end
      end
    end
  end

  def assert_actions(exp, response)
    actions = response.results.pluck("action")
    assert_same_elements exp, actions
  end

  def build_projects_query(project, latest_allowed_entry_time: nil)
    Search::Queries::Audit::ProjectQuery.new(project: project, index_name: @audit_log_test_helper_index.name, latest_allowed_entry_time: latest_allowed_entry_time)
  end

  def assert_responses
    response = @deleted_time_query.execute
    assert_equal 3, response.total
    assert_actions ["project.create", "project.update", "project.delete"], response
    response = @updated_time_query.execute
    assert_equal 2, response.total
    assert_actions ["project.create", "project.update"], response
    response = @created_time_query.execute
    assert_equal 1, response.total
    assert_actions ["project.create"], response
  end
end
