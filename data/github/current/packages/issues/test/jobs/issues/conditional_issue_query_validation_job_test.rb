# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Issues::ConditionalIssueQueryValidationJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper

  fixtures do
    @user = create(:user)
  end

  unless GitHub.enterprise?
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
