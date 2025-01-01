# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Public::Usage::QueryBuilderTest < GitHub::TestCase
  fixtures do
    @business = create(:business)
    @org = create(:organization, business: @business)
    @repo = create(:repository, owner: @org)

    @different_org = create(:organization)
    @different_repo = create(:repository, owner: @different_org)
  end

  context "#build" do
    test "sets year, month, day and hour to now by default for this year's usage" do
      Timecop.freeze("2025-08-24 00:01:00Z") do
        query = Billing::Public::Usage::QueryBuilder.build(@business, period: BillingSettingsHelper::USAGE_PERIOD[:this_year])
        now = Time.now.utc
        assert_equal query[:billing_period], BillingPlatform::Base::BillingPeriod::Yearly
        assert_equal query[:year], now.year
        assert_equal query[:month], now.month
        assert_equal query[:day], now.day
        assert_equal query[:hour], now.hour
      end
    end

    test "sets year, month, day and hour to now by default for this month's usage" do
      Timecop.freeze("2025-08-24 00:01:00Z") do
        query = Billing::Public::Usage::QueryBuilder.build(@business, period: BillingSettingsHelper::USAGE_PERIOD[:this_month])
        assert_equal query[:billing_period], BillingPlatform::Base::BillingPeriod::Monthly
        now = Time.now.utc
        assert_equal query[:year], now.year
        assert_equal query[:month], now.month
        assert_equal query[:day], now.day
        assert_equal query[:hour], now.hour
      end
    end

    test "sets year, month, day and hour to now by default for today's usage" do
      Timecop.freeze("2025-08-24 00:01:00Z") do
        query = Billing::Public::Usage::QueryBuilder.build(@business, period: BillingSettingsHelper::USAGE_PERIOD[:today])
        assert_equal query[:billing_period], BillingPlatform::Base::BillingPeriod::Daily
        now = Time.now.utc
        assert_equal query[:year], now.year
        assert_equal query[:month], now.month
        assert_equal query[:day], now.day
        assert_equal query[:hour], now.hour
      end
    end

    test "sets year, month, day and hour to now by default for this hour's usage" do
      Timecop.freeze("2025-08-24 00:01:00Z") do
        query = Billing::Public::Usage::QueryBuilder.build(@business, period: BillingSettingsHelper::USAGE_PERIOD[:this_hour])
        assert_equal query[:billing_period], BillingPlatform::Base::BillingPeriod::Hourly
        now = Time.now.utc
        assert_equal query[:year], now.year
        assert_equal query[:month], now.month
        assert_equal query[:day], now.day
        assert_equal query[:hour], now.hour
      end
    end

    test "sets month and year to last month for last month's usage" do
      Timecop.freeze("2025-08-24 00:01:00Z") do
        query = Billing::Public::Usage::QueryBuilder.build(@business, period: BillingSettingsHelper::USAGE_PERIOD[:last_month])
        assert_equal query[:billing_period], BillingPlatform::Base::BillingPeriod::Monthly
        now = Time.now.utc
        assert_equal query[:month], now.last_month.month
        assert_equal query[:year], now.last_month.year
      end
    end

    test "sets year to last year for last year's usage" do
      Timecop.freeze("2025-08-24 00:01:00Z") do
        query = Billing::Public::Usage::QueryBuilder.build(@business, period: BillingSettingsHelper::USAGE_PERIOD[:last_year])
        assert_equal query[:billing_period], BillingPlatform::Base::BillingPeriod::Yearly
        now = Time.now.utc
        assert_equal query[:year], now.last_year.year
      end
    end

    test "sets billingPeriod to monthly when no period is present" do
      query = Billing::Public::Usage::QueryBuilder.build(@business)
      assert_equal query[:billing_period], BillingPlatform::Base::BillingPeriod::Monthly
    end

    context "product param" do
      test "does not set product field when product is missing" do
        query = Billing::Public::Usage::QueryBuilder.build(@business)
        assert_nil query[:product]
      end

      test "sets product field when product is present" do
        query = Billing::Public::Usage::QueryBuilder.build(@business, product: "actions")
        assert_equal query[:product], "actions"
      end
    end

    context "group param" do
      test "does not set group_by field when group is missing" do
        query = Billing::Public::Usage::QueryBuilder.build(@business)
        assert_nil query[:group_by]
      end

      test "sets group_by field when group is present" do
        query = Billing::Public::Usage::QueryBuilder.build(@business, group: BillingPlatform::Base::UsageGroupBy::GroupByProduct.to_s)
        assert_equal query[:group_by], BillingPlatform::Base::UsageGroupBy::GroupByProduct
      end
    end

    context "when query is present" do
      test "sets org_id field when org is present in the query" do
        input_org_query = "org:#{@org.login}"
        query = Billing::Public::Usage::QueryBuilder.build(@business, query: input_org_query)
        assert_equal query[:org_id], @org.id
      end

      test "sets org_id field to -1 when org is present in the query but invalid" do
        input_repo_query = "org:invalid"
        query = Billing::Public::Usage::QueryBuilder.build(@business, query: input_repo_query)
        assert_equal query[:org_id], -1
      end

      test "sets org_id field to -1 when an org is present in the query but does not belong to the business" do
        input_org_query = "org:#{@different_org.login}"
        query = Billing::Public::Usage::QueryBuilder.build(@business, query: input_org_query)
        assert_equal query[:org_id], -1
      end

      test "sets repo_id field when repo is present in the query" do
        input_repo_query = "repo:#{@repo.nwo}"
        query = Billing::Public::Usage::QueryBuilder.build(@business, query: input_repo_query)
        assert_equal query[:repo_id], @repo.id
      end

      test "sets repo_id field to -1 when a repo is present in the query but invalid" do
        input_repo_query = "repo:github/does-not-exist"
        query = Billing::Public::Usage::QueryBuilder.build(@business, query: input_repo_query)
        assert_equal query[:repo_id], -1
      end

      test "sets repo_id field to -1 when a repo is present in the query but does not belong to the business" do
        input_repo_query = "repo:#{@different_repo.nwo}"
        query = Billing::Public::Usage::QueryBuilder.build(@business, query: input_repo_query)
        assert_equal query[:repo_id], -1
      end

      test "sets product field when product is present in the query" do
        query = Billing::Public::Usage::QueryBuilder.build(@business, query: "product:actions")
        assert_equal query[:product], "actions"
      end

      test "sets sku field when sku is present in the query" do
        query = Billing::Public::Usage::QueryBuilder.build(@business, query: "sku:actions_linux")
        assert_equal query[:sku], "actions_linux"
      end

      test "sets both sku and product field when sku and product is present in the query" do
        query = Billing::Public::Usage::QueryBuilder.build(@business, query: "product:actions sku:actions_linux")
        assert_equal query[:sku], "actions_linux"
        assert_equal query[:product], "actions"
      end

      test "sets cost_center_id field with none when cost_center none is present in the query" do
        input_cost_center_query = "cost_center:None"
        expected_cost_center_id = "none"
        query = Billing::Public::Usage::QueryBuilder.build(@business, query: input_cost_center_query)
        assert_equal query[:cost_center_id], expected_cost_center_id
      end

      test "does not set query fields when grouping by organization" do
        query = Billing::Public::Usage::QueryBuilder.build(@business, query: "product:actions", group: BillingPlatform::Base::UsageGroupBy::GroupByOrganization.to_s)
        assert_nil query[:product]
      end

      test "does not set query fields when grouping by repostiory" do
        query = Billing::Public::Usage::QueryBuilder.build(@business, query: "product:actions", group: BillingPlatform::Base::UsageGroupBy::GroupByRepository.to_s)
        assert_nil query[:product]
      end
    end
  end
end
