# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/filter_test_helper"

class LabelsLoaderTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user)
    @repository = create(:repository)
    @issue = create(:issue, repository: @repository)
    @label1 = create(:label, name: "bug", repository: @repository)
    @label2 = create(:label, name: "feature", repository: @repository)
    @context = Issue::Adapter::Context.new(@issue, @repository, @user, cap_filter: cap_authorizing_filter)

    Issue::Loader::CurrentIssue.load_for(@context)
    Issue::Loader::CurrentRepository.load_for(@context)
  end

  test "loading labels only executes expected queries" do
    result, queries = log_queries do
      Issue::Loader::Labels.load_for(@context, label_ids: [@label1.id, @label2.id])
    end

    # 1 query for loading all labels
    expected_count = 1
    assert_equal expected_count, queries.count

    assert_equal 2, result.size
    assert result.to_h.include?(@label1.id)
    assert result.to_h.include?(@label2.id)
  end
end
