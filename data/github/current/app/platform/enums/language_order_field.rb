# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class LanguageOrderField < Platform::Enums::Base
      description "Properties by which language connections can be ordered."

      value "SIZE", "Order languages by the size of all files containing the language", value: "size"
    end
  end
end
