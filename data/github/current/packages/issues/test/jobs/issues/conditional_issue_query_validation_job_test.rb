# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Issues::ConditionalIssueQueryValidationJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
    5.times do
      issue = create(:issue, repository: @repo)
      issue.labels = [create(:label, repository: @repo)]
      make_searchable(issue)
    end
  end

  setup do
    GitHub.flipper[:issues_advanced_search].disable
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  unless GitHub.enterprise?
    # TODO: Add a test verifying that we call IssueQuery.new with the correct parameters

    test "a non-complex query returns no mismatches" do
      phrase = "label:#{Label.first.name}"
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      # Assert that no Scientist::Experiment::MismatchError is raised
      assert_nothing_raised do
        Issues::ConditionalIssueQueryValidationJob.perform_now(
          allow_insecure_user_to_server_app_query: nil,
          current_user: @user,
          user_session: nil,
          repo_id: nil,
          remote_ip: nil,
          current_installation: nil,
          aggregations: nil,
          phrase:,
          highlight: nil,
          normalizer: nil,
          source_fields: nil,
          context: nil,
          catalog_service: nil,
        )
      end

      assert_equal 1, GitHub.dogstats.increments("science", tags: ["experiment:search.conditional_issue_query_validation", "result:match"]).length
    end

    test "logs a result" do
      phrase = "please find me some things"
      expected = {
        "Body": "ConditionalIssueQueryValidationJob Results",
        "gh.enduser.login": @user.display_login,
        "gh.issues_advanced_search.query": phrase,
      }

      assert_logged(**expected) do
        Issues::ConditionalIssueQueryValidationJob.perform_now(
          allow_insecure_user_to_server_app_query: nil,
          current_user: @user,
          user_session: nil,
          repo_id: nil,
          remote_ip: nil,
          current_installation: nil,
          aggregations: nil,
          phrase:,
          highlight: nil,
          normalizer: nil,
          source_fields: nil,
          context: nil,
          catalog_service: nil,
        )
      end
    end
  end
end
