# typed: true
# frozen_string_literal: true

require "test_helper"

class LabelDiscussionDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:verified_user)
    @repo = create(:repository, owner: @user, has_discussions: true)
    @label = create(:label, repository: @repo)
    @issue = create(:issue, repository: @repo, user: @user, labels: [@label])
  end

  context "#convertable_issues" do
    test "includes open issue" do
      result = @label.convertable_issues(@user)

      assert_includes result, @issue
    end
  end
end
