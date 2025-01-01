# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/filter_test_helper"

class DiscussionsLoaderTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  fixtures do
    @user = create(:user)
    @repository = create(:repository, has_discussions: true)
    @issue = create(:issue, repository: @repository)
    @discussion = create(:discussion, repository: @repository)

    @event, @other_event = create_list(:issue_event, 2,
      event: "converted_to_discussion",
      subject: @discussion,
      actor: @repository.owner,
    )
  end

  test "loading projects only executes expected queries" do
    context = Issue::Adapter::Context.new(
      @issue,
      @repository,
      @user,
      cap_filter: cap_authorizing_filter,
    )
    Issue::Loader::CurrentIssue.load_for(context)
    Issue::Loader::CurrentRepository.load_for(context)

    # simlulate preload from show_loader
    [@event, @other_event].each do |event|
      event.association(:issue_event_detail).load_target
    end

    Platform::Security::RepositoryAccess.with_viewer(@user) do
      result, queries = log_queries do
        Issue::Loader::Discussions.load_for(
          context,
          conversion_events: [@event, @other_event],
        )
      end

      # 1 query to load all discussions
      assert_equal 1, queries.count
      assert_equal 2, result.size
      assert_equal [@event.id, @discussion], result.shift
      assert_equal [@other_event.id, @discussion], result.shift
    end
  end

  test "no queries executed if there aren't any conversion_events" do
    context = Issue::Adapter::Context.new(
      @issue,
      @repository,
      @user,
      cap_filter: cap_authorizing_filter,
    )
    Issue::Loader::CurrentIssue.load_for(context)
    Issue::Loader::CurrentRepository.load_for(context)

    Platform::Security::RepositoryAccess.with_viewer(@user) do
      result, queries = log_queries do
        Issue::Loader::Discussions.load_for(
          context,
          conversion_events: [],
        )
      end

      assert_equal 0, queries.count
      assert_equal 0, result.size
    end
  end
end
