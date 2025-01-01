# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/filter_test_helper"

class DuplicateIssuesLoaderTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user)
    @repository = create(:repository)

    @canonical_issue1 = create(:issue, repository: @repository)
    @issue1 = create(:issue, repository: @repository)
    @issue2 = create(:issue, repository: @repository)

    @canonical_issue2 = create(:issue, repository: @repository)
    @issue3 = create(:issue, repository: @repository)
    @issue4 = create(:issue, repository: @repository)

    DuplicateIssue.find_or_build_for(issue: @issue1, canonical_issue: @canonical_issue1, user: @user).save
    DuplicateIssue.find_or_build_for(issue: @issue2, canonical_issue: @canonical_issue1, user: @user).save
    DuplicateIssue.find_or_build_for(issue: @issue3, canonical_issue: @canonical_issue2, user: @user).save
    DuplicateIssue.find_or_build_for(issue: @issue4, canonical_issue: @canonical_issue2, user: @user).save


    @context = Issue::Adapter::Context.new(@issue, @repository, @user, cap_filter: cap_authorizing_filter)

    Issue::Loader::CurrentIssue.load_for(@context)
    Issue::Loader::CurrentRepository.load_for(@context)
  end

  test "loading duplicate issues only executes expected queries" do
    canonical_and_issue_ids = [
      [@canonical_issue1.id, @issue1.id],
      [@canonical_issue1.id, @issue2.id],
      [@canonical_issue2.id, @issue3.id],
      [@canonical_issue2.id, @issue4.id]
    ]
    result, queries = log_queries do
      Issue::Loader::DuplicateIssues.load_for(@context, canonical_and_issue_ids: canonical_and_issue_ids)
    end

    # 1 query for loading all duplicate issues
    expected_count = 1
    assert_equal expected_count, queries.count

    assert_equal 4, result.size
    assert result.to_h.include?([@canonical_issue1.id, @issue1.id])
    assert result.to_h.include?([@canonical_issue1.id, @issue2.id])
    assert result.to_h.include?([@canonical_issue2.id, @issue3.id])
    assert result.to_h.include?([@canonical_issue2.id, @issue4.id])
  end
end
