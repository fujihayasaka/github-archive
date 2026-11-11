# typed: true
# frozen_string_literal: true

# Utilities for imposing conditional filters,
# e.g. FilterWhenLanguage can be used to only
# create read-only task lists when the language
# of the file is detected as "Markdown."

module GitHub
  module HTML
    # Another filter for applying other filters based on the language of the file
    class FilterWhenNotLanguage
      def name
        %Q{FilterWhenNotLanguage: #{@language}}
      end

      def initialize(language, filter)
        @filter = filter
        @language = language.to_s
      end

      def call(input, context, result)
        path = context[:name] || context[:path]
        return @filter.call(input, context, result) if path.blank?
        languages = Linguist::Language.find_by_filename(path)
        languages = Linguist::Language.find_by_extension(path) if languages.empty?
        if !languages.any? { |l| l.name == @language }
          @filter.call(input, context, result)
        else
          input
        end
      end
    end
  end
end
