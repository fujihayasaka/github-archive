# typed: true
# frozen_string_literal: true

# Do not require anything here. If you need something else, require it in the method that needs it.
# This makes sure the boot time of our seeds stays low.

module Seeds
  module Objects
    module Copilot
      class CodingGuideline
        DEFAULT_GUIDELINE_NAME = "Concise test descriptions"
        DEFAULT_GUIDELINE_DESCRIPTION = <<~DESCRIPTION
          For tests of the structure
          ```
          test "<test description>" do
            # test code is here ...
          end
          ```
          ensure <test description> is concise and less than 5 words.
          DESCRIPTION

        GUIDELINES_SAMPLE_CODE = {
          test_description_length: {
            filename: "test/sample_test.rb",
            contents: <<~TEST
            # frozen_string_literal: true

            class SampleTest < GitHub::IntegrationTest
              test "very long description - emits Hydro event for opening Copilot chat from banner" do
                @user.enable_feature(:copilot_reviews)

                as @user
                request_env["HTTP_REFERER"] = referer_url
                post "/github-copilot/monalisa/smile/pulls/review-banner/sha123/sha456", xhr: true

                assert_response :ok
                expected_context = Hydro::EntitySerializer.request_context(GitHub.context.to_hash)
                assert_equal referer_url, expected_context[:referrer]
              end
            end
            TEST
          },
          spelling: {
            filename: "math.rb",
            contents: <<~MATH
            class Math
              # Public: divids given numbbers
              def diviide(a, b)
                a / b
              end
            end
            MATH
          }
        }

        def self.create(
          repo:,
          name: DEFAULT_GUIDELINE_NAME,
          description: DEFAULT_GUIDELINE_DESCRIPTION,
          paths_attributes: []
        )
          ::Copilot::CodingGuideline.create!(
            repository: repo,
            name:,
            description:,
            paths_attributes:
          )
        end
      end
    end
  end
end
