# typed: true
# frozen_string_literal: true

require "test_helper"

class MandatoryMessageTest < GitHub::TestCase

  fixtures do
    @user = create(:user, login: "user", email: "user@example.com")
    @markdown = <<~MARKDOWN
      ## Welcome

      Please read this carefully and check the box below.

      - [ ] I have read everything
    MARKDOWN
  end

  setup do
    MandatoryMessage.set(@markdown)
  end

  teardown do
    MandatoryMessage.del
  end

  context "::set" do
    test "updates mandatory message value" do
      MandatoryMessage.set("Hello World")
      assert_equal true, MandatoryMessage.exists?
      assert_equal "Hello World", MandatoryMessage.value
    end

    test "does not clear viewed records for all users by default" do
      another = create :user
      MandatoryMessage.set_user_viewed(@user)
      MandatoryMessage.set_user_viewed(another)
      assert MandatoryMessage.user_viewed?(@user)
      assert MandatoryMessage.user_viewed?(another)

      perform_enqueued_jobs only: [ClearMandatoryMessageViewsJob] do
        MandatoryMessage.set("Hello World")
      end

      assert_predicate MandatoryMessage, :exists?
      assert_equal "Hello World", MandatoryMessage.value
      assert MandatoryMessage.user_viewed?(@user)
      assert MandatoryMessage.user_viewed?(another)
    end

    test "clears viewed records for all users when clear_existing_viewed_records is true" do
      another = create :user
      MandatoryMessage.set_user_viewed(@user)
      MandatoryMessage.set_user_viewed(another)
      assert MandatoryMessage.user_viewed?(@user)
      assert MandatoryMessage.user_viewed?(another)

      perform_enqueued_jobs only: [ClearMandatoryMessageViewsJob] do
        MandatoryMessage.set("Hello World", clear_existing_viewed_records: true)
      end

      assert_predicate MandatoryMessage, :exists?
      assert_equal "Hello World", MandatoryMessage.value
      refute MandatoryMessage.user_viewed?(@user)
      refute MandatoryMessage.user_viewed?(another)
    end
  end if GitHub.enterprise?

  context "::del" do
    test "delete message" do
      MandatoryMessage.del
      assert_equal false, MandatoryMessage.exists?
      assert_nil MandatoryMessage.value
    end
  end

  context "::html" do
    test "generates HTML correctly with single checkbox" do
      assert_equal <<~HTML.chomp, MandatoryMessage.html
        <h2>Welcome</h2>
        <p>Please read this carefully and check the box below.</p>
        <ul class=\"contains-task-list\">
        <li class=\"task-list-item\"><input type=\"checkbox\" name=\"checkboxes[box_1]\" required=\"\" class=\"task-list-item-checkbox\"> I have read everything</li>
        </ul>
      HTML
    end

    test "generates HTML correctly with multiple checkboxes" do
      md = <<~MD
        ## One two three

        - [ ] One
        - [ ] Two
        - [ ] Three
      MD
      MandatoryMessage.set(md)

      assert_equal <<~HTML.chomp, MandatoryMessage.html
        <h2>One two three</h2>
        <ul class=\"contains-task-list\">
        <li class=\"task-list-item\"><input type=\"checkbox\" name=\"checkboxes[box_1]\" required=\"\" class=\"task-list-item-checkbox\"> One</li>
        <li class=\"task-list-item\"><input type=\"checkbox\" name=\"checkboxes[box_2]\" required=\"\" class=\"task-list-item-checkbox\"> Two</li>
        <li class=\"task-list-item\"><input type=\"checkbox\" name=\"checkboxes[box_3]\" required=\"\" class=\"task-list-item-checkbox\"> Three</li>
        </ul>
      HTML
    end
  end

  context "::checkbox_count" do
    test "returns 0 when there are no checkboxes" do
      MandatoryMessage.set("Hello")
      assert_equal 0, MandatoryMessage.checkbox_count
    end

    test "returns 1 when there is 1 checkbox" do
      md = <<~MD
        ## One only

        - [ ] One
      MD
      MandatoryMessage.set(md)
      assert_equal 1, MandatoryMessage.checkbox_count
    end

    test "returns 3 when there are 3 checkboxes" do
      md = <<~MD
        ## One two three

        - [ ] One
        - [ ] Two
        - [ ] Three
      MD
      MandatoryMessage.set(md)
      assert_equal 3, MandatoryMessage.checkbox_count
    end
  end

  context "::set_user_viewed" do
    test "mark as viewed" do
      assert_equal false, MandatoryMessage.user_viewed?(@user)

      events = subscribe "user.mandatory_message_viewed"
      expected_payload = {
        copy_hash: Digest::SHA256.hexdigest(@markdown),
        actor: @user.login,
        actor_id: @user.id
      }

      MandatoryMessage.set_user_viewed(@user)

      assert event = events.pop, "an event was expected"
      assert_equal "user.mandatory_message_viewed", event.name
      assert_equal expected_payload, event.payload

      assert_equal true, MandatoryMessage.user_viewed?(@user)
    end
  end

  context "::unset_user_viewed" do
    test "mark as not viewed" do
      MandatoryMessage.set_user_viewed(@user)
      assert MandatoryMessage.user_viewed?(@user)

      MandatoryMessage.unset_user_viewed(@user)
      refute MandatoryMessage.user_viewed?(@user)
    end
  end
end
