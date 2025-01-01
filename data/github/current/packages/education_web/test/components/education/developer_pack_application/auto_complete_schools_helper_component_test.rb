# typed: true
# frozen_string_literal: true

require "test_helper"

# rubocop:disable ViewComponent/EncouragePreviewsForScannableComponents
module Education::DeveloperPackApplication
  class AutoCompleteSchoolsHelperComponentTest < GitHub::TestCase
    include GitHub::ComponentTestHelpers

    test "it renders the hidden tags and the react partial" do
      render_inline AutoCompleteSchoolsHelperComponent.new

      assert_test_selector("autocomplete-schools-helper-react-partial")
    end
  end
end
# rubocop:enable ViewComponent/EncouragePreviewsForScannableComponents
