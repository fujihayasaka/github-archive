# typed: strict
# frozen_string_literal: true

module Site
  module Contentful
    module Helpers
      module FixtureHelper
        # This is a helper method to generate a JSON file with the raw JSON response from Contentful.
        # This can be used in tests to modify valid JSON responses to create purposefully invalid responses.
        #
        # To use, run: script/site/generate_contentful_fixture
        #
        # @param file_name [String] the name of the file to be created (without the .json extension)
        # @param contentful_raw_json_response [Hash] the raw JSON response from Contentful
        # @return [Integer] the number of bytes written to the file
        sig { params(file_name: T.untyped, contentful_raw_json_response: T.untyped).returns(Integer) }
        def self.generate(file_name, contentful_raw_json_response)
          File.open("test/fixtures/site/contentful/#{file_name}.json", "w") do |file|
            file.write(JSON.pretty_generate(contentful_raw_json_response))
          end
        end
      end
    end
  end
end
