# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionPollBuilderTest < GitHub::TestCase
  fixtures do
    @user = create(:verified_user)
    @repo = create(:repository, owner: @user, has_discussions: true)
    @category = DiscussionCategory.find_by(slug: "polls")
  end

  test "create a discussion poll" do
    body = <<~EOS
    ```poll
    question: what?
    options:
      - option 1
      - option 2
    ```
  EOS
    @discussion = Discussion.create(title: "first poll", user: @user, body: body, repository: @repo, category: @category)
    @builder = DiscussionPoll::Builder.new(@discussion, @user)

    poll = @builder.build(question: "what?", options: ["option 1", "option 2"])
    options = poll.options.map(&:option)

    assert_equal "what?", poll.question
    assert_equal "option 1", options[0]
    assert_equal "option 2", options[1]
  end
end
