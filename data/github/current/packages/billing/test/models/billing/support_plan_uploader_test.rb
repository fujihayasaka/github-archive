# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::SupportPlanUploaderTest < GitHub::BillingTestCase

  def create_csv(id:, plan:)
    headers = %w(id support_plan)
    @accounts_file = Tempfile.new("project_harmony.csv")
    CSV.open(@accounts_file, "a+") do |row|
      row << headers
      row << [id, plan]
    end
  end

  def support_plan_uploader(accounts_file:)
    Billing::SupportPlanUploader.new(accounts_file: accounts_file)
  end

  setup do
    GitHub.flipper[:microsoft_support_plan].enable
  end

  test "leaves GitHub support plan unchanged" do
    business = create(:business, support_plan: "standard")
    create_csv(id: business.id, plan: "education")


    support_plan_uploader(accounts_file: @accounts_file).perform

    assert_equal "standard", business.reload.support_plan
  end

  test "updates microsoft support plan for business" do
    business = create(:business, support_plan: "standard")
    create_csv(id: business.id, plan: "premium_premier")


    support_plan_uploader(accounts_file: @accounts_file).perform

    assert_equal "premium_premier", business.reload.microsoft_support_plan
    assert_equal "standard", business.reload.support_plan
  end

  test "returns amount of accounts updated" do
    business = create :business, support_plan: "standard"

    create_csv(id: business.id, plan: "premium_unified")

    result = support_plan_uploader(accounts_file: @accounts_file).perform

    assert_equal "premium_unified", business.reload.microsoft_support_plan

    assert_equal 1, result[:count_of_accounts_updated]
  end

  test "does not allow invalid support plan" do
    business = create :business, support_plan: "standard"
    create_csv(id: business.id, plan: "premium_standard")

    support_plan_uploader(accounts_file: @accounts_file).perform

    assert_nil business.reload.microsoft_support_plan
  end

  test "returns business_ids_not_found" do
    create_csv(id: -1, plan: "premium_premier")

    result = support_plan_uploader(accounts_file: @accounts_file).perform

    assert result[:business_ids_not_found].include?(-1)
  end
end
