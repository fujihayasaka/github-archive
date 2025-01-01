# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class LanguageNameByName < Platform::Loader
      def self.load(name)
        self.for.load(name)
      end

      def fetch(names)
        ::LanguageName.where(name: names).index_by(&:name)
      end
    end
  end
end
