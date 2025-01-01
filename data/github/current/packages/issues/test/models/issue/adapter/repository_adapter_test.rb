# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryAdapterTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper
  include GitHub::PullRequestTestHelpers

  test "adapting a repository can check for feature flags" do
    pull = make_pr_and_repos
    repo = pull.repository
    issue = create(:issue, repository: repo)
    viewer = issue.user
    feature = create(:feature_with_flipper)
    loader = Issue::ShowLoader.new issue, repo, viewer, cap_filter: cap_authorizing_filter
    adapted = Issue::Adapter::RepositoryAdapter.new(loader.context, repository: repo)
    feature.flipper_feature.enable(repo)

    assert_equal repo.feature_enabled?(feature.slug.to_sym), adapted.feature_enabled?(feature.slug.to_sym)

  end
end
