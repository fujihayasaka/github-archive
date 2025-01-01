# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotPromptBaseTest < GitHub::TestCase
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
      "@#{user.display_login}"
    end

    def expand_item(user)
      user.inspect
    end
  end

  class TestPromptTemplate < Copilot::Prompt::Template
    include ViewComponent::InlineTemplate

    PromptItem = type_member { { fixed: User } }

    erb_template <<~ERB
    <%= message_with(role: "system") do -%>
    <%- items.each do |item| %>
    - <%= references.encode(item) %>
    <%- end -%>
    <%- end -%>
    ERB
  end

  fixtures do
    @monalisa = create(:user, login: "monalisa")
    @collaborator = create(:user)
  end

  setup do
    @prompt = TestPrompt.new
  end

  context "#add_item?" do
    test "returns whether or not there is enough token budget to add a new item" do
      assert @prompt.add_item?(@monalisa), "expected enough space to add one item"

      @prompt.expected_response_tokens = 60..70
      refute @prompt.add_item?(@monalisa), "expected NOT enough space to add item"
    end
  end

  context "#add_item" do
    test "adds the item" do
      @prompt.add_item(@monalisa)
      assert_includes @prompt.items, @monalisa
    end

    test "increments the expected response token" do
      before = @prompt.expected_response_tokens
      @prompt.add_item(@monalisa)

      expected = (before.min + 20)..(before.max + 30)
      assert_equal expected, @prompt.expected_response_tokens
    end
  end

  context "#render" do
    test "renders the template" do
      @prompt.add_item @monalisa

      rendered = @prompt.render
      assert_includes rendered, "- @monalisa"
    end
  end

  context "#references" do
    test "are cleared on each render" do
      @prompt.add_item @monalisa
      @prompt.render

      assert_includes @prompt.references, @monalisa

      @prompt.add_item? @collaborator
      assert_includes @prompt.references, @collaborator

      @prompt.render
      refute_includes @prompt.references, @collaborator
    end
  end

  context "#messages" do
    test "are cleared on each render" do
      @prompt.add_item @monalisa
      @prompt.render

      assert_includes @prompt.messages.map(&:to_h), { role: "system", content: "- @monalisa\n" }

      @prompt.add_item? @collaborator
      assert_includes @prompt.messages.map(&:to_h), { role: "system", content: "- @monalisa\n- @#{@collaborator}\n" }

      @prompt.render
      refute_includes @prompt.messages.map(&:to_h), { role: "system", content: "- @#{@collaborator}\n" }
    end
  end
end
