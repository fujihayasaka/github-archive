# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotPromptReferenceEncoderTest < GitHub::TestCase
  class TestPrompt < Copilot::Prompt::Base

    PromptItem = type_member { { fixed: User } }

    def max_tokens
      80
    end

    def baseline_expected_response_tokens
      10..20
    end

    def per_item_expected_response_tokens
      20..30
    end

    def encode_item(user)
      "@#{user.login}"
    end

    def expand_item(user)
      "<a href=\"/#{user.login}\">@#{user.login}</a>"
    end
  end

  fixtures do
    @monalisa = create(:user, login: "monalisa")
    @monalisa_2 = create(:user, login: "monalisa2")
    @defunkt = create(:user, login: "defunkt")
  end

  setup do
    @prompt = TestPrompt.new
    @encoder = Copilot::Prompt::ReferenceEncoder[User].new(prompt: @prompt)
  end

  test "encodes items based on the prompt's rules" do
    assert_equal "@monalisa", @encoder.encode(@monalisa)
  end

  test "decodes and expands all encoded references" do
    @encoder.encode @monalisa
    @encoder.encode @monalisa_2 # add a user second with a longer login that starts with the same characters as the first user
    @encoder.encode @defunkt

    input = <<~INPUT
      Hi, we're @monalisa2, @monalisa, @defunkt, and @hubot.
    INPUT
    expected = <<~EXPECTED
      Hi, we're <a href="/monalisa2">@monalisa2</a>, <a href="/monalisa">@monalisa</a>, <a href="/defunkt">@defunkt</a>, and @hubot.
    EXPECTED

    assert_equal expected, @encoder.decode_and_expand_all(input)
  end
end
