# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/filter_test_helper"

class UnmarkedAsDuplicateEventAdapterTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  test "adapting a mark as duplicate event does not execute any queries" do
    user = create(:user)
    other_user = create(:user)
    repo = create(:repository, owner: user)
    create(:profile, user: user)

    issue1 = create(:issue, repository: repo, body: "issue body", user: user)
    issue2 = create(:issue, repository: repo, body: "issue body", user: user)

    create(:issue_event, event: "unmarked_as_duplicate", issue: issue1, subject: issue2, actor: user)

    Platform::Security::RepositoryAccess.with_viewer(user) do
      loader = Issue::ShowLoader.new issue1, repo, user, cap_filter: cap_authorizing_filter
      event = loader.context.events.find { |e| e.event == "unmarked_as_duplicate" }
      _adapted, queries = log_cleaned_queries do
        Issue::Adapter::UnmarkedAsDuplicateEventAdapter.new(loader.context, event_id: event.id)
      end
      assert_equal 0, queries.count
    end
  end
end
