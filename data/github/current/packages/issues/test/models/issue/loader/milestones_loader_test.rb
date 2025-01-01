# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/filter_test_helper"

class MilestonesLoaderTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user)
    @repository = create(:repository)
    @issue = create(:issue, repository: @repository)
    @milestone1 = create(:milestone, repository: @repository, title: "Release 2.0")
    @milestone2 = create(:milestone, repository: @repository, title: "Release 3.0")
    @milestone_event1 = create(:issue_event, event: "milestoned", issue: @issue, actor: @user, milestone_id: @milestone1.id, milestone_title: @milestone1.title)
    # legacy style
    @milestone_event2 = create(:issue_event, event: "milestoned", issue: @issue, actor: @user, milestone_title: @milestone2.title)
    @milestone_event2.save!
  end

  setup do
    @context = Issue::Adapter::Context.new(@issue, @repository, @user, cap_filter: cap_authorizing_filter)
    Issue::Loader::CurrentIssue.load_for(@context)
    Issue::Loader::CurrentRepository.load_for(@context)
  end

  test "loading milestones only executes expected queries" do
    # simlulate preload from show_loader
    [@milestone_event1, @milestone_event2].each do |e|
      e.association(:issue_event_detail).load_target
    end

    result, queries = log_queries do
      Issue::Loader::Milestones.load_for(@context, milestone_events: [@milestone_event1, @milestone_event2])
    end

    # 1 query for loading milestones by id
    # 1 query for loading milestones by title
    expected_count = 2
    assert_equal expected_count, queries.count

    assert_equal 2, result.size
    assert_equal @milestone1,  result[@milestone_event1.id]
    assert_equal @milestone2, result[@milestone_event2.id]
  end
end
