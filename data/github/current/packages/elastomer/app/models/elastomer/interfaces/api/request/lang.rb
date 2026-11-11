# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Request
        # An enum representing the possible values for the `lang` parameter in the `script` field of an Elasticsearch request.
        #
        # See https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-scripting.html for more information.
        class Lang < T::Enum
          enums do
            Painless = new("painless")
            Expression = new("expression")
            Mustache = new("mustache")
            Java = new("java")
          end
        end
      end
    end
  end
end
