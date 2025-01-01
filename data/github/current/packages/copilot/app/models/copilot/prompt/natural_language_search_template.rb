# typed: strict
# frozen_string_literal: true
module Copilot
  module Prompt
    class NaturalLanguageSearchTemplate < ::Copilot::Prompt::Template
      PromptItem = type_member { { fixed: String } }

      sig { returns(Copilot::Prompt::NaturalLanguageSearch) }
      def prompt
        T.cast(super, Copilot::Prompt::NaturalLanguageSearch)
      end
    end
  end
end
