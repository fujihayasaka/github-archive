# typed: true
# frozen_string_literal: true

require "test_helper"

class UserHovercardSubjectDefinitionTest < GitHub::TestCase
  fixtures do
    @user = create(:user, created_at: 1.year.ago)
  end

  test "allows async_user_hovercard_contexts_for to return []" do
    primary_subject = Organization.new
    primary_subject.stubs(:async_user_hovercard_contexts_for).returns([])

    hovercard = UserHovercard.new(@user, primary_subject, viewer: @user)

    assert_equal [], hovercard.contexts
  end

  test "allows async_user_hovercard_contexts_for to return a promise that resolves to nil" do
    primary_subject = Organization.new
    primary_subject.stubs(:async_user_hovercard_contexts_for).returns([Promise.resolve(nil)])

    hovercard = UserHovercard.new(@user, primary_subject, viewer: @user)

    assert_equal [], hovercard.contexts
  end

  test "allows async_user_hovercard_contexts_for to return a promise that resolves to a real value" do
    primary_subject = Organization.new
    primary_subject.stubs(:async_user_hovercard_contexts_for).returns([Promise.resolve(1)])

    hovercard = UserHovercard.new(@user, primary_subject, viewer: @user)

    assert_equal [1], hovercard.contexts
  end
end
