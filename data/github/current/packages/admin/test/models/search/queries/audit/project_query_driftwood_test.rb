# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesAuditProjectQueryDriftwoodTest < GitHub::TestCase
  include AuditLogHelpers

  unless GitHub.enterprise?
    fixtures do
      @user = create(:user, login: "usethis", plan: "medium", email: "user@fake.org")
      @org = create(:organization)
      @org.add_member(@user)

      @repo = create(:repository, owner: @org)

      @repo_project = create(:project, owner: @repo, name: "Project 1")
      @repo_project2 = create(:project, owner: @repo, name: "Project 2")
    end

    setup do
      GitHub.stubs(:driftwood_enabled?).returns(true)

      @es_query = {
        current_user: @user,
        user_id: @user.id,
        actor_id: @user.id,
        org_id: @org.id,
        project: @repo_project,
        phrase: "created",
        page: 1,
        feature_flags: %w[flag1 flag2],
      }
    end

    context "date range" do
      test "limits project results by latest_allowed_entry_time in correct time zones" do
        created_time = Time.at(1411413154).in_time_zone("Pacific Time (US & Canada)") # 2014-09-22 12:12:34 -0700

        Time.use_zone("Pacific Time (US & Canada)") do
          Timecop.freeze(created_time) do
            @es_query[:latest_allowed_entry_time] = created_time.to_s
            query = Audit::Driftwood::Query.new_project_query(@es_query)
            query_timestamp = Time.at(query.driftwood_query.request.latest_allowed_entry_time.to_i).to_datetime

            assert_equal query.org, @org
            assert_instance_of Driftwood::TwirpRequest::ProjectQuery, query.driftwood_query
            assert_instance_of Audit::Driftwood::Query, query
            assert_equal query.driftwood_query.request.project_id, @repo_project.id
            assert_equal query.driftwood_query.request.per_page, 50
            assert_equal query_timestamp, created_time.to_s
          end
        end

        Time.use_zone("Australia/Sydney") do
          Timecop.freeze(created_time) do
            @es_query[:latest_allowed_entry_time] = created_time.to_s
            query = Audit::Driftwood::Query.new_project_query(@es_query)
            query_timestamp = Time.at(query.driftwood_query.request.latest_allowed_entry_time.to_i).to_datetime

            assert_equal query.org, @org
            assert_instance_of Driftwood::TwirpRequest::ProjectQuery, query.driftwood_query
            assert_instance_of Audit::Driftwood::Query, query
            assert_equal query.driftwood_query.request.project_id, @repo_project.id
            assert_equal query.driftwood_query.request.per_page, 50
            assert_equal query_timestamp, created_time.to_s
          end
        end

        Time.use_zone("Europe/Paris") do
          Timecop.freeze(created_time) do
            @es_query[:latest_allowed_entry_time] = created_time.to_s
            query = Audit::Driftwood::Query.new_project_query(@es_query)
            query_timestamp = Time.at(query.driftwood_query.request.latest_allowed_entry_time.to_i).to_datetime

            assert_equal query.org, @org
            assert_instance_of Driftwood::TwirpRequest::ProjectQuery, query.driftwood_query
            assert_instance_of Audit::Driftwood::Query, query
            assert_equal query.driftwood_query.request.project_id, @repo_project.id
            assert_equal query.driftwood_query.request.per_page, 50
            assert_equal query_timestamp, created_time.to_s
          end
        end
      end
    end
  end
end
