# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class StepBuilder::FlashTest < GitHub::TestCase
    include GitHub::UserDefinedCommandTestHelpers

    fixtures do
      add_file_to_commands("flash.yml", <<~YAML)
        ---
        trigger: flash
        title: Flash
        steps:
        - type: flash
          template: Hi, my name is **{{ command.user.login }}**
      YAML
    end

    test "displays render markdown flash message" do
      command = build_user_defined_command("flash", subject: @issue)

      command.process

      assert_equal command.flash.notice, "Hi, my name is <strong>monalisa</strong>"
    end

    test "escapes malicious content" do
      add_file_to_commands("bad_flash.yml", <<~YAML)
        ---
        trigger: bad_flash
        title: Flash
        steps:
        - type: flash
          template: "<script>alert('hi')</script>"
      YAML

      command = build_user_defined_command("bad_flash", subject: @issue)

      command.process

      assert_equal command.flash.notice, "&lt;script&gt;alert('hi')&lt;/script&gt;"
    end
  end
end
