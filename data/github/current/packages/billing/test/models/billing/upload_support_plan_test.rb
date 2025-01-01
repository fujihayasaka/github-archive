# typed: strict
# frozen_string_literal: true

require "test_helper"

class Billing::UploadSupportPlanTest < GitHub::BillingTestCase

  sig { params(out: T.untyped, id: Integer, plan: String).returns(CSV) }
  def create_csv(out:, id:, plan:)
    headers = %w(id support_plan)
    CSV.open(out, "a+") do |row|
      row << headers
      row << [id, plan]
    end
  end

  setup do
    GitHub.flipper[:microsoft_support_plan].enable
  end

  test "updates microsoft support plan for business" do
    business = create(:business, support_plan: "standard")
    accounts_file = Tempfile.new("project_harmony.csv")
    create_csv(out: accounts_file, id: business.id, plan: "premium_premier")


    ::Billing::UploadSupportPlan.call(accounts_file: accounts_file)

    assert_equal "premium_premier", business.reload.microsoft_support_plan
  end
end
