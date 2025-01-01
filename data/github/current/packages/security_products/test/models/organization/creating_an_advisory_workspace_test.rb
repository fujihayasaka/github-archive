# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationCreatingAnAdvisoryWorkspaceTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @repo = create(:private_repository, owner: @org)
    @advisory = create(:repository_advisory, :with_workspace, repository: @repo)
  end

  test "doesn't count toward private repo count" do
    assert_equal 2, @org.owned_private_repositories.count
    assert_equal 1, @org.private_repo_count_for_limit_check
  end
end
