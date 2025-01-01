# typed: strict
# frozen_string_literal: true

# Public: A template used for rendering the prompt. Built off of ViewComponents for convenience.
#
# Examples
#
#   class MyPrompt < Copilot::Prompt::Base
#   end
#
#   # Template class must match prompt class naming with 'Template' appended'
#   # path/to/my_prompt_template.rb
#   class MyPromptTemplate < Copilot::Prompt::Template
#     def title(str)
#       str.titleize
#     end
#   end
#
#   # path/to/my_prompt_template.text.erb
#   Hello <%= title context.current_user %>
#
#
#   prompt = MyPrompt.new(context: Copilot::Prompt::Context.new(current_user: "monalisa"))
#   prompt.render
#   # => "Hello Monalisa"
#
module Copilot
  module Prompt
    class Template < ViewComponent::Base
      extend T::Sig
      extend T::Generic

      PromptItem = type_member

      sig { returns(Copilot::Prompt::Base[PromptItem]) }
      attr_reader :prompt

      delegate :items, :references, to: :prompt

      sig { params(prompt: Copilot::Prompt::Base[PromptItem]).void }
      def initialize(prompt)
        @prompt = prompt
      end

      # This method can be used within your templates if you plan to split a given prompt up into messages to send
      # to the copilot API. This approach allows you to keep all your copy in one template file for easier reference.
      # For example this generates a message on the prompt with a role of "system":
      #
      #   <%= message_with(role: "system") do -%>
      #     Assistant is a senior software engineer explaining a pull request to a junior software engineer.
      #   <%- end -%>
      #
      # When `prompt.render` is called, these messages are collected on the prompt so that they can be easily
      # retrieved via `prompt.messages`. You can reference these files for an example use-case where messages
      # are collected in the template and used in the copilot API call made in the pipeline:
      #   - packages/pull_requests/app/lib/pull_requests/copilot/prompt/v1/overall_summary_template.text.erb
      #   - packages/pull_requests/app/lib/pull_requests/copilot/prompt/v1/summary_pipeline.rb
      sig { params(role: String, block: T.untyped).returns(T.untyped) } # rubocop:disable Sorbet/ForbidTUntyped
      def message_with(role:, &block)
        content = capture(&block)
        prompt.messages << Message.new(role:, content:)
        content
      end
    end
  end
end
