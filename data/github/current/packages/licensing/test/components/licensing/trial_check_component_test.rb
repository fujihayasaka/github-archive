# typed: true
# frozen_string_literal: true

require "test_helper"

class Licensing::TrialCheckComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  test "Success rendered when not on trial" do
    business = create(:business)
    business.stub(:trial?, false) do
      render_inline(Licensing::TrialCheckComponent.new(business: business), allowed_queries: 1)
      assert_test_selector("trial-check", text: "Not on a trial")
    end
  end

  test "Error rendered when on trial" do
    business = create(:business)
    business.stub(:trial?, true) do
      render_inline(Licensing::TrialCheckComponent.new(business: business), allowed_queries: 1)
      assert_test_selector("trial-check", text: "Currently on a trial")
    end
  end
end
