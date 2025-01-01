# typed: true
# frozen_string_literal: true

require "test_helper"

class SurveyGroupTest < GitHub::TestCase
  test "is destroyed when the corresponding user is destroyed" do
    group = create(:survey_group)
    refute_nil SurveyGroup.last
    user = group.user
    user.destroy
    assert_nil SurveyGroup.last
  end
end
