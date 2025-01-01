# typed: true
# frozen_string_literal: true

require "test_helper"
require "github/tagging_helper"

# this tests the functionality in lib/github/tagging_helper.rb but just for codespaces
class TaggingHelperTest < GitHub::TestCase
  def test_codespaces_automated_testing
    test_cases = {
      "non-production and test user" => {
        env: {
          GitHub::TaggingHelper::RACK_REQUEST_PARAMETERS_KEY => {
            "vscs_target" => "ppe",
          },
          GitHub::TaggingHelper::CODESPACES_AUTOMATED_TESTING => true,
        },
        result: true,
      },
      "non-production and not test user" => {
        env: {
          GitHub::TaggingHelper::RACK_REQUEST_PARAMETERS_KEY => {
            "vscs_target" => "ppe",
          },
          GitHub::TaggingHelper::CODESPACES_AUTOMATED_TESTING => false,
        },
        result: true,
      },
      "production and test user" => {
        env: {
          GitHub::TaggingHelper::RACK_REQUEST_PARAMETERS_KEY => {
            "vscs_target" => "production",
          },
          GitHub::TaggingHelper::CODESPACES_AUTOMATED_TESTING => true,
        },
        result: true,
      },
      "production and not test user" => {
        env: {
          GitHub::TaggingHelper::RACK_REQUEST_PARAMETERS_KEY => {
            "vscs_target" => "production",
          },
          GitHub::TaggingHelper::CODESPACES_AUTOMATED_TESTING => false,
        },
        result: false,
      }
    }

    test_cases.each do |name, test_case|
      if test_case[:result]
        assert GitHub::TaggingHelper.codespaces_automated_testing?(test_case[:env]), "Expected codespaces_automated_testing? to be true for #{name}"
      else
        refute GitHub::TaggingHelper.codespaces_automated_testing?(test_case[:env]), "Expected codespaces_automated_testing? to be false for #{name}"
      end
    end
  end
end
