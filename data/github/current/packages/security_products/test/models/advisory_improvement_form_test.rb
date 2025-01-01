# typed: true
# frozen_string_literal: true

require "test_helper"

class AdvisoryImprovementFormTest < GitHub::TestCase
  test "passed advisory should not be mutated" do
    advisory = create(:vulnerability, description: "Initially different", summary: nil)
    params = { description: "Some description", summary: "New summary" }

    AdvisoryImprovementForm.new(params, advisory)

    assert_equal "Initially different", advisory.description
    refute advisory.summary
    refute advisory.changed?
  end
end
