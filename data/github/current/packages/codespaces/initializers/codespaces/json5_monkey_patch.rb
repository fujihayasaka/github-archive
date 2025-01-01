# typed: true
# frozen_string_literal: true

require "json5"

Rails.configuration.after_initialize do
  module Codespaces
    module SafeJSON5Parser
      # This version simply makes it so duplicate keys don't throw matching the
      # Codespace agent/service parsing implementations (in typescript and C# respectively).
      def object
        ### BEGIN MONKEY PATCH SECTION
        T.bind(self, JSON5::Parser)
        ### END MONKEY PATCH SECTION

        # Parse an object value.
        ### BEGIN MONKEY PATCH SECTION
        key = T.let(nil, T.nilable(String)) # was `key = nil`
        ### END MONKEY PATCH SECTION
        object = {}

        ### BEGIN MONKEY PATCH SECTION
        if T.unsafe(@ch == "{") # was `if @ch == "{"`
          ### END MONKEY PATCH SECTION
          get_next("{")
          white
          while @ch do
            if @ch == "}"
              get_next("}")
              return object;   # Potentially empty object
            end

            # Keys can be unquoted. If they are, they need to b
            # valid JS identifiers.
            if @ch == "\"" || @ch == "'"
              key = string
            else
              key = identifier
            end

            white
            get_next(":")

            ### BEGIN MONKEY PATCH SECTION
            # We always need to call value here to ensure we parse the contents properly.
            parsed_value = value
            # But we only add it to our parsed object if we haven't already hit this same
            # key in this object before.
            object[key] = parsed_value unless object.has_key?(key)
            ### END MONKEY PATCH SECTION
            white
            # If there's no comma after this pair, this needs to b
            # the end of the object.
            if @ch != ","
              get_next("}")
              return object
            end
            get_next(",")
            white
          end
        end
        error("Bad object")
      end
    end
  end

  JSON5::Parser.prepend(Codespaces::SafeJSON5Parser)
end
