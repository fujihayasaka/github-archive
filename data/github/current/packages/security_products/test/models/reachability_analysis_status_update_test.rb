# typed: true
# frozen_string_literal: true

require "test_helper"

class ReachabilityAnalysisStatusUpdateTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @repo = create(:private_repository, :private, owner: @org)
    @analysis = create(:reachability_analysis, repository: @repo)
  end

  test "can be created" do
    status = create(:reachability_analysis_status_update, reachability_analysis: @analysis)

    assert_equal 1, @analysis.status_updates.count
    assert_equal status, @analysis.status_updates.first

    status2 = create(:reachability_analysis_status_update, reachability_analysis: @analysis)
    assert_equal 2, @analysis.status_updates.count
    assert_equal status2, @analysis.status_updates.second
  end
end
