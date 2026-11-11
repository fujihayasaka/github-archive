# typed: true
# frozen_string_literal: true

module SlashCommands
  class CodeCommand < ApplicationSlashCommand
    category :markdown

    trigger_on name: "code", title: "Code block", description: "Insert a code block formatted for a chosen syntax"

    menu :languages
    fill :fill_block

    def languages
      languages = (relevant_languages + default_languages).uniq.compact.map do |lang|
        Item.new(id: lang.name, text: lang.name, value: lang.default_alias_name)
      end

      # include "No Syntax" item to insert a generic code block
      languages.prepend(Item.new(text: "No Syntax", value: ""))

      menu(:language, items: languages)
    end

    def fill_block
      <<~CODEBLOCK
      ```#{data[:language]}
      %cursor%
      ```
      CODEBLOCK
    end

    private

    def default_languages
      Linguist::Language.popular
    end

    # Look at the current repository's language analysis to put the most relevant languages near the top
    def relevant_languages
      current_repo = context.current_repository
      return [] if current_repo.nil?

      current_repo.language_percentages.map do |name, _|
        Linguist::Language.find_by_name(name)
      end
    end
  end
end
