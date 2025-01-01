# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsors::BulkSponsorshipBlankTemplateTest < GitHub::TestCase
  setup do
    skip unless GitHub.sponsors_enabled?
  end

  context ".to_csv" do
    test "returns a CSV with the correct headers and example values" do
      expected_csv = "Maintainer username,Sponsorship amount in USD\n" \
        "maintainerUsername1,100 or $100\n" \
        "maintainerUsername2,100 or $100\n"

      assert_equal expected_csv, Sponsors::BulkSponsorshipBlankTemplate.to_csv
    end
  end
end
