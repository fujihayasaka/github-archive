# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotPromptBuilderTest < GitHub::TestCase
  include DogstatsTestHelpers

  class TestPrompt < Copilot::Prompt::Base

    PromptItem = type_member { { fixed: String } }

    def max_tokens
      80
    end

    def baseline_expected_response_tokens
      20..30
    end

    def per_item_expected_response_tokens
      20..30
    end

    def encode_item(item)
      item.to_s
    end

    def expand_item(item)
      item.inspect
    end

    attr_reader :current_user

    def initialize(current_user:)
      super()
      @current_user = current_user
    end
  end

  class TestPromptTemplate < Copilot::Prompt::Template
    include ViewComponent::InlineTemplate

    PromptItem = type_member { { fixed: String } }

    erb_template <<~ERB
    <%- items.each do |item| %>
    - <%= references.encode(item) %>
    <%- end -%>
    ERB
  end

  fixtures do
    @user = create :user
  end

  setup do
    @items = %w(foo bar baz)
    @builder = Copilot::Prompt::Builder[TestPrompt, String].new items: @items
    @builder.prompt_template = -> { TestPrompt.new(current_user: @user) }
  end

  context "#prompts" do
    test "builds prompt(s) with the supplied items" do
      prompts = @builder.prompts
      assert_equal 2, prompts.count
      first, second = prompts

      assert_same_elements %w(foo bar), first.items
      assert_same_elements %w(baz), second.items
      assert_dogstats_timing(1, "copilot.prompt.builder_prompts", tags: ["size:3", "prompt_class:CopilotPromptBuilderTest::TestPrompt"])
    end

    test "uses the prompt template to build the prompts" do
      prompts = @builder.prompts

      prompts.each do |prompt|
        assert_equal @user, prompt.current_user
      end
    end
  end

  context "#item_too_big_strategy" do
    test "drops items by default" do
      TestPrompt.any_instance.expects(:add_item?).times(4).returns(true, false)

      prompts = @builder.prompts
      assert_equal 1, prompts.count
      assert_same_elements %w(foo), prompts.first.items
    end

    test "can be given a strategy" do
      TestPrompt.any_instance.expects(:add_item?).times(6).returns(false, true)
      @builder.item_too_big_strategy = -> (item) do
        item.chars
      end

      prompt, _ = @builder.prompts
      assert_same_elements %w(f o o bar baz), prompt.items
    end
  end
end
