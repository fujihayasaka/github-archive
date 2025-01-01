# typed: true
# frozen_string_literal: true

require "test_helper"

# rubocop:disable ViewComponent/EncouragePreviewsForScannableComponents
module Education::DeveloperPackApplication
  class AutoCompleteSchoolsComponentTest < GitHub::TestCase
    include GitHub::ComponentTestHelpers

    test "it renders autocomplete items for the given schools" do
      schools = [
        { "school_id" => 1, "name" => "School 1" },
        { "school_id" => 2, "name" => "School 2" },
      ]

      render_inline AutoCompleteSchoolsComponent.new(
        schools:,
        user_has_two_factor_auth_enabled: false,
        user_verified_emails: [],
      )

      assert_test_selector("autocomplete-item-school-1", text: "School 1")
      assert_test_selector("autocomplete-item-school-2", text: "School 2")
    end
  end
end
# rubocop:enable ViewComponent/EncouragePreviewsForScannableComponents
