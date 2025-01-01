# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/filter_test_helper"


class CommentAdapterTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  fixtures do
    @user  = create(:user, :with_profile)
    @staff = create(:staff_admin_user)
    @repo  = create(:repository, owner: @user)
    @issue = create(:issue, repository: @repo, user: @user)
  end

  context "queries" do
    test "author_association causes no queries" do
      comment = create(:issue_comment, issue: @issue)
      loader = Issue::ShowLoader.new(@issue, @repo, @user, cap_filter: cap_authorizing_filter)
      symbol, queries = log_cleaned_queries do
        result = Issue::Adapter::CommentAdapter.new(loader.context, comment_id: comment.id, issue_adapter: {})
        result.author_association_symbol
      end
      assert_equal 0, queries.count
      assert_equal :owner, symbol
    end
  end

  context "comment race handling" do
    test "handles missing comments gracefully" do
      loader = Issue::ShowLoader.new(@issue, @repo, @user, cap_filter: cap_authorizing_filter)

      result = Issue::Adapter::CommentAdapter.new(loader.context, comment_id: 123, issue_adapter: {})
      assert_nil result
    end
  end

  context "#stafftools_url" do
    test "returns stafftools URL for staff viewer" do
      comment = create(:issue_comment, issue: @issue)
      loader = Issue::ShowLoader.new(@issue, @repo, @staff, cap_filter: cap_authorizing_filter)
      result = Issue::Adapter::CommentAdapter.new(loader.context, comment_id: comment.id, issue_adapter: {})
      assert_equal comment.stafftools_url, result.stafftools_url
    end

    test "returns nil for non-staff viewer" do
      comment = create(:issue_comment, issue: @issue)
      loader = Issue::ShowLoader.new(@issue, @repo, @user, cap_filter: cap_authorizing_filter)
      result = Issue::Adapter::CommentAdapter.new(loader.context, comment_id: comment.id, issue_adapter: {})
      assert_nil result.stafftools_url
    end
  end
end
