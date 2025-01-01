# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class StepBuilder::AddCommentTest < GitHub::TestCase
    include GitHub::UserDefinedCommandTestHelpers

    fixtures do
      add_file_to_commands("hello.yml", <<~YAML)
        ---
        trigger: hello
        title: Hello
        steps:
          - type: addComment
            id: makeComment
            body: Hi there, my name is {{ command.user.login }}
      YAML
    end

    test "add comment to issue from user" do
      command = build_user_defined_command("hello", subject: @issue)

      assert_difference -> { @issue.comments.count }, 1 do
        command.process
      end

      comment = @issue.comments.last
      assert_equal "Hi there, my name is #{@owner.login}", comment.body
      assert_equal @owner, comment.user
    end

    test "returns new comment global relay id" do
      command = build_user_defined_command("hello", subject: @issue)

      command.process

      comment = @issue.comments.last
      expected_data = {
        "makeComment" => {
          "id" => comment.global_relay_id,
          "bodyText" => comment.body
        }
      }

      assert_equal command.data, expected_data
    end

    test "fails when user isn't allowed to comment" do
      other_user = create(:user)
      command = build_user_defined_command("hello", current_user: other_user, subject: @issue)

      assert_no_difference -> { @issue.comments.count } do
        command.process
      end

      assert_includes command.flash.error, "Problem while executing step 1 (makeComment)"
    end
  end
end
