# typed: true
# frozen_string_literal: true

# Replace ActiveSupport's JSON encoding and decoding with GitHub::JSON
require "active_support/json"

module ActiveSupport
  module JSON
    def self.decode(json, options = {})
      data = GitHub::JSON.load(json, options)

      if ActiveSupport.parse_json_times
        convert_dates_from(data)
      else
        data
      end
    end

    # Use GitHub::JSON for encoding
    def self.encode(obj, options = {})
      # call #as_json to ensure everything we pass to it is a type that yajl
      # can convert to a native JSON type. Otherwise it will call #to_json on
      # the object, which will lead to an infinite loop.
      GitHub::JSON.encode(obj.as_json(options), options)
    end
  end
end
