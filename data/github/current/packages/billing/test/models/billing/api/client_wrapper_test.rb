# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Api::ClientWrapperTest < GitHub::TestCase
  include ::Billing::ApiTestHelpers
  include DogstatsTestHelpers
  include GitHub::LoggerHelper

  fixtures do
    @business = create(:business, :with_azure_subscription)
    @organization = create(:organization, business: @business)
    @user = create(:user)
  end

  setup do
    @client_wrapper = Billing::Api::ClientWrapper.new(billable_owner: @business, owner: @organization)
    @start_at = Google::Protobuf::Timestamp.new(seconds: 1.day.ago.beginning_of_day.to_i)
    @end_at = Time.now
  end

  context "Initialization" do
    test "Uses default timeout " do
      @client_wrapper_default =  Billing::Api::ClientWrapper.new(billable_owner: @business, owner: @organization)
      meuse_connection = @client_wrapper_default.meuse_client.send("connection")
      assert_equal(meuse_connection.options.timeout, 15)
    end

    test "It can override default timeout" do
      @client_wrapper_custom = Billing::Api::ClientWrapper.new(billable_owner: @business, owner: @organization, timeout: 10)
      meuse_connection = @client_wrapper_custom.meuse_client.send("connection")
      assert_equal(meuse_connection.options.timeout, 10)
    end
  end

  context "API wrapper methods" do
    context "#list_account_usage" do
      test "returns expected usage" do
        mock_list_account_usage_response(product: "codespaces", unit_of_measure: "Hours", quantity: 1000.0)
        result = @client_wrapper.list_account_usage(@start_at)
        assert_equal(result[:account_usage][0][:account][:account_id], 4242)
        assert_equal(result[:account_usage][0][:account][:account_type], :OWNER_TYPE_USER)
        assert_equal(result[:account_usage][0][:product_usage][0][:product][:name], "codespaces")
        assert_equal(result[:account_usage][0][:product_usage][0][:product_sku][:unit_of_measure][:name], "Hours")
        assert_equal(result[:account_usage][0][:product_usage][0][:usage][:quantity], 1000.0)
      end

      test "returns BillingClientError when error occurs" do
        mock_list_account_usage_response_error

        assert_logged("exception.type" => Billing::Api::ClientWrapper::BillingClientError.name) do
          result = @client_wrapper.list_account_usage(@start_at)
          assert_equal(result.class, Billing::Api::ClientWrapper::BillingClientError)
          assert_equal(result.original_error.class, Twirp::Error)
          assert_equal(1, Failbot.reports.size)
        end
      end
    end

    context "#get_usage_breakdown" do
      test "returns expected usage" do
        skus = Billing::CodespacesUsage::ALL_SKUS.map do |sku_name|
          create_skus_breakdown_hash(
            sku: sku_name,
            budget_ids: [1],
            estimated_overage_charge: 100
          )
        end

        mock_get_usage_breakdown(
          entitlements: [create_entitlement_hash(name: "Codespaces - Compute", exhausted: true)],
          products: create_product_breakdown_array(name: "codespaces", skus: skus)
        )

        result = @client_wrapper.get_usage_breakdown(product_names: ["codespaces"])
        codespace_products = result[:product_breakdowns].find { |product| product[:name] = "codespaces" }[:sku_breakdowns]

        assert_equal(result[:entitlements][0][:name], "Codespaces - Compute")
        assert_equal(result[:entitlements][0][:allocated_quantity], 1000.0)
        assert_equal(result[:entitlements][0][:consumed_quantity], 1000.0)
        assert_equal(codespace_products.length, Billing::CodespacesUsage::ALL_SKUS.length)
        assert_equal(codespace_products[0][:name], "compute_d2")
        assert_equal(codespace_products[0][:budget_ids], [1])
        assert_equal(codespace_products[0][:raw_quantities][:total], 300.0)
        assert_equal(codespace_products[0][:raw_quantities][:entitlement], 100.0)
        assert_equal(codespace_products[0][:raw_quantities][:overage], 200.0)
        assert_equal(codespace_products[0][:entitlement_details][:id], 1)
        assert_equal(codespace_products[0][:entitlement_details][:multiplier], 1)
        assert_equal(codespace_products[0][:entitlement_details][:quantity_consumed], 100.0)
      end

      test "returns BillingClientError when error occurs" do
        mock_get_usage_breakdown_response_error

        assert_logged("exception.type" => Billing::Api::ClientWrapper::BillingClientError.name) do
          result = @client_wrapper.get_usage_breakdown(product_names: ["codespaces"])
          assert_equal(result.class, Billing::Api::ClientWrapper::BillingClientError)
          assert_equal(result.original_error.class, Twirp::Error)
          assert_equal(1, Failbot.reports.size)
        end
      end
    end

    context "#get_entitlement_plans" do
      test "returns expected plan entitlements" do
        mock_get_entitlement_plans

        result = @client_wrapper.get_entitlement_plans(plan_name: "free")

        assert_equal(result[:entitlement_plans].count, 5)
      end
    end

    context "#list_product_usage" do
      test "returns expected usage" do
        mock_list_product_usage_response(product: "codespaces", unit_of_measure: "Hours", quantity: 1000.0)
        result = @client_wrapper.list_product_usage(@start_at)
        assert_equal(result[:product_usage][0][:product][:name], "codespaces")
        assert_equal(result[:product_usage][0][:product_sku][:unit_of_measure][:name], "Hours")
        assert_equal(result[:product_usage][0][:usage][:quantity], 1000.0)
      end

      test "returns BillingClientError when error occurs" do
        mock_list_product_usage_response_error

        assert_logged("exception.type" => Billing::Api::ClientWrapper::BillingClientError.name) do
          result = @client_wrapper.list_product_usage(@start_at)
          assert_equal(result.class, Billing::Api::ClientWrapper::BillingClientError)
          assert_equal(result.original_error.class, Twirp::Error)
          assert_equal(1, Failbot.reports.size)
        end
      end
    end

    context "#calculate_usage_quotes" do
      test "returns expected usage quote" do
        mock_calculate_usage_quotes_response(
          usage_quotes: [
            {
              product_name: "actions",
              product_sku_name: "linux",
              total_historical_usage: { effective_quantity: 5, estimated_cost: { currency_code: "USD", subunits: 500 } },
            },
            {
              product_name: "packages",
              product_sku_name: "default",
              total_historical_usage: { effective_quantity: 25, estimated_cost: { currency_code: "USD", subunits: 2500 } },
            },
          ]
        )

        proposed_usage = [
          {
            product_name: "actions",
            product_sku_name: "linux",
          },
          {
            product_name: "packages",
            product_sku_name: "default",
          }
        ]

        result = @client_wrapper.calculate_usage_quotes(proposed_usage, @start_at)
        actions_usage_quote = result[:usage_quotes].find { |quote| quote.actions_linux? }

        assert_equal(actions_usage_quote.product_name, "actions")
        assert_equal(actions_usage_quote.product_sku_name, "linux")
        assert_equal(actions_usage_quote[:total_historical_usage][:effective_quantity], 5)
        assert_equal(actions_usage_quote[:total_historical_usage][:estimated_cost][:subunits], 500)

        packages_usage_quote = result[:usage_quotes].find { |quote| quote.packages? }

        assert_equal(packages_usage_quote.product_name, "packages")
        assert_equal(packages_usage_quote.product_sku_name, "default")
        assert_equal(packages_usage_quote[:total_historical_usage][:effective_quantity], 25)
        assert_equal(packages_usage_quote[:total_historical_usage][:estimated_cost][:subunits], 2500)
      end

      test "returns BillingClientError when error occurs" do
        mock_calculate_usage_quotes_response_error

        proposed_usage = [
          {
            product_name: "actions",
            product_sku_name: "linux",
          },
          {
            product_name: "packages",
            product_sku_name: "default",
          }
        ]

        assert_logged("exception.type" => Billing::Api::ClientWrapper::BillingClientError.name) do
          result = @client_wrapper.calculate_usage_quotes(proposed_usage, @start_at)
          assert_equal(result.class, Billing::Api::ClientWrapper::BillingClientError)
          assert_equal(result.original_error.class, Twirp::Error)
          assert_equal(1, Failbot.reports.size)
        end
      end
    end

    context "#update_submission_details" do
      test "calls the UpdateSubmissionDetails API" do
        mock_update_submission_details_response

        result = @client_wrapper.update_submission_details(@start_at)

        refute_instance_of(result.class, Billing::Api::ClientWrapper::BillingClientError)
      end

      test "returns BillingClientError when error occurs" do
        mock_update_submission_details_response_error

        assert_logged("exception.type" => Billing::Api::ClientWrapper::BillingClientError.name) do
          result = @client_wrapper.update_submission_details(@start_at)
          assert_equal(result.class, Billing::Api::ClientWrapper::BillingClientError)
          assert_equal(result.original_error.class, Twirp::Error)
          assert_equal(1, Failbot.reports.size)
        end
      end
    end

    context "#get_usage_line_items" do
      test "returns expected usage line items" do
        usage_at = Google::Protobuf::Timestamp.new(seconds: 2.days.ago.beginning_of_day.to_i)
        mock_get_usage_line_items_response(
          repository_id: 1,
          custom_fields: { "checkrun.id" => "12345" },
          usage_at: usage_at
        )
        result = @client_wrapper.get_usage_line_items(
          product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:actions],
          usage_starts_at: 3.days.ago.beginning_of_day,
          usage_ends_at: 1.day.ago.beginning_of_day,
          custom_fields: { "checkrun.id" => { "field_values" => ["12345"] } }
        )
        usage_line_item = result[0]

        assert_equal(usage_line_item.repository_id, 1)
        assert_equal(usage_line_item.usage_at, usage_at)
        assert_equal(usage_line_item.custom_fields, { "checkrun.id": "12345" })
      end

      test "repeats API calls when there is next_page" do
        first_usage_at = Google::Protobuf::Timestamp.new(seconds: 3.days.ago.beginning_of_day.to_i)
        other_usage_at = Google::Protobuf::Timestamp.new(seconds: 2.days.ago.beginning_of_day.to_i)
        last_usage_at = Google::Protobuf::Timestamp.new(seconds: 1.day.ago.beginning_of_day.to_i)


        api_response_sequence = [
          create_mock_twirp_usage_line_item(usage_at: first_usage_at, repository_id: 1, next_page: 2, custom_fields: { "checkrun.id" => "123" }),
          create_mock_twirp_usage_line_item(usage_at: other_usage_at, repository_id: 2, next_page: 3),
          create_mock_twirp_usage_line_item(usage_at: other_usage_at, repository_id: 2, next_page: 4),
          create_mock_twirp_usage_line_item(usage_at: other_usage_at, repository_id: 2, next_page: 5),
          create_mock_twirp_usage_line_item(usage_at: last_usage_at, repository_id: 3, next_page: 0, custom_fields: { "checkrun.id" => "321" })
        ]

        Meuse::Client.any_instance.expects(:get_usage_line_items).times(5).returns(*api_response_sequence)

        result = @client_wrapper.get_usage_line_items(
          product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:actions],
          usage_starts_at: 4.days.ago.beginning_of_day,
          usage_ends_at: Time.now.beginning_of_day,
          custom_fields: { "checkrun.id" => { "field_values" => %w[123 111 321] } }
        )

        assert_equal(result.size, 5)

        first_usage_line_item = result.first
        assert_equal(first_usage_line_item.repository_id, 1)
        assert_equal(first_usage_line_item.usage_at, first_usage_at)
        assert_equal(first_usage_line_item.custom_fields, { "checkrun.id": "123" })

        last_usage_line_item = result.last
        assert_equal(last_usage_line_item.repository_id, 3)
        assert_equal(last_usage_line_item.usage_at, last_usage_at)
        assert_equal(last_usage_line_item.custom_fields, { "checkrun.id": "321" })
      end

      test "returns BillingClientError when error occurs" do
        mock_get_usage_line_items_response_error

        assert_logged("exception.type" => Billing::Api::ClientWrapper::BillingClientError.name) do
          result = @client_wrapper.get_usage_line_items(product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:actions])
          assert_equal(result.class, Billing::Api::ClientWrapper::BillingClientError)
          assert_equal(result.original_error.class, Twirp::Error)
          assert_equal(1, Failbot.reports.size)
        end
      end

      test "returns partial result when subsequent API call fails and 'allow_partial_result' is true" do
        api_response_sequence = [
          create_mock_twirp_usage_line_item(repository_id: 1, next_page: 2),
          create_mock_twirp_usage_line_item(repository_id: 2, next_page: 3),
          Twirp::ClientResp.new(data: nil, error: Twirp::Error.new(:unavailable, "unavailable")),
          create_mock_twirp_usage_line_item(repository_id: 3, next_page: 0)
        ]

        Meuse::Client.any_instance.expects(:get_usage_line_items).times(3).returns(*api_response_sequence)

        assert_logged("exception.type" => Billing::Api::ClientWrapper::BillingClientError.name) do
          result = @client_wrapper.get_usage_line_items(
            product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:actions],
            allow_partial_result: true
          )

          assert_equal(result.size, 2)
          assert_equal(result.last.repository_id, 2)
          refute_equal(result.class, Billing::Api::ClientWrapper::BillingClientError)
          assert_equal(1, Failbot.reports.size)
        end
      end

      test "returns error when subsequent API call fails and 'allow_partial_result' is false" do
        api_response_sequence = [
          create_mock_twirp_usage_line_item(repository_id: 1, next_page: 2),
          create_mock_twirp_usage_line_item(repository_id: 2, next_page: 3),
          Twirp::ClientResp.new(data: nil, error: Twirp::Error.new(:unavailable, "unavailable")),
          create_mock_twirp_usage_line_item(repository_id: 3, next_page: 0)
        ]

        Meuse::Client.any_instance.expects(:get_usage_line_items).times(3).returns(*api_response_sequence)

        assert_logged("exception.type" => Billing::Api::ClientWrapper::BillingClientError.name) do
          result = @client_wrapper.get_usage_line_items(
            product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:actions],
            allow_partial_result: false
          )

          assert_equal(result.class, Billing::Api::ClientWrapper::BillingClientError)
          assert_equal(result.original_error.class, Twirp::Error)
          assert_equal(1, Failbot.reports.size)
        end
      end

      test "retries when Twirp error is retryable and 'additional_retries' is true" do
        api_response_sequence = [
          Twirp::ClientResp.new(data: nil, error: Net::ReadTimeout.new),
          Twirp::ClientResp.new(data: nil, error: Net::ReadTimeout.new),
          Twirp::ClientResp.new(data: nil, error: Net::ReadTimeout.new),
          create_mock_twirp_usage_line_item(repository_id: 3, next_page: 0)
        ]

        Meuse::Client.any_instance.expects(:get_usage_line_items).times(4).returns(*api_response_sequence)

        result = @client_wrapper.get_usage_line_items(
          product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:actions],
          additional_retries: true
        )

        usage_line_item = result.first
        assert_equal(usage_line_item.repository_id, 3)

        assert_dogstats_increment(1, "billing.client.twirp_retries", tags: ["retries:3"])
      end

      test "retries when error is thrown outside of Twirp response and 'additional_retries' is true" do
        Meuse::Client.any_instance.expects(:get_usage_line_items)
          .returns(create_mock_twirp_usage_line_item(repository_id: 1, next_page: 2))
        Meuse::Client.any_instance.expects(:get_usage_line_items).with(has_entry(page: 2))
          .returns(create_mock_twirp_usage_line_item(repository_id: 2, next_page: 3))
        Meuse::Client.any_instance.expects(:get_usage_line_items).with(has_entry(page: 3)).twice
          .raises(Net::ReadTimeout)
          .then.returns(create_mock_twirp_usage_line_item(repository_id: 3, next_page: 0))

        result = @client_wrapper.get_usage_line_items(
          product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:actions],
          additional_retries: true
        )

        first_usage_line_item = result.first
        assert_equal(first_usage_line_item.repository_id, 1)

        last_usage_line_item = result.last
        assert_equal(last_usage_line_item.repository_id, 3)

        expected_tags = [
          "retry_attempt:1",
          "billable_owner_id:#{@business.id}",
          "billable_owner_type:OWNER_TYPE_BUSINESS"
        ]

        assert_dogstats_increment(1, "billing.client.rescue_retries", tags: expected_tags)
      end

      test "does not retry Twirp errors when 'additional_retries' is false" do
        api_response_sequence = [
          Twirp::ClientResp.new(data: nil, error: Net::ReadTimeout.new)
        ]

        Meuse::Client.any_instance.expects(:get_usage_line_items).times(1).returns(*api_response_sequence)

        result = @client_wrapper.get_usage_line_items(
          product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:actions],
          additional_retries: false
        )

        assert_equal(result.class, Billing::Api::ClientWrapper::BillingClientError)
      end
    end

    context "when retrying transient errors" do
      test "instruments increment of retries" do
        stub_request(:any, /meuse/).to_raise(Faraday::ConnectionFailed)
        expected_tags = [
          "rpc:meuse.services.v1.MeteredUsage/ListAccountUsage",
          "error:Faraday::ConnectionFailed",
        ]

        result = @client_wrapper.list_account_usage(@start_at)

        assert_dogstats_increment(2, "billing.client.retry", tags: expected_tags)
        # Instruments a single error
        assert_dogstats_increment(1, "billing.client.error")
        assert_equal(result.class, Billing::Api::ClientWrapper::BillingClientError)
        assert_equal(result.original_error.class, Faraday::ConnectionFailed)
        assert_equal(1, Failbot.reports.size)
      end
    end
  end

  context "codespaces methods" do
    context "#codespaces_monthly_usage" do
      test "returns all product usage for codespaces" do
        mock_list_product_usage_response(product: "codespaces", unit_of_measure: "Hours", quantity: 1000.0)
        result = @client_wrapper.codespaces_monthly_usage
        assert_equal(result[:product_usage][0][:product][:name], "codespaces")
        assert_equal(result[:product_usage][0][:product_sku][:unit_of_measure][:name], "Hours")
        assert_equal(result[:product_usage][0][:usage][:quantity], 1000.0)
      end
    end

    context "#codespaces_skus" do
      test "returns a list of all avilable codespaces skus" do
        result = @client_wrapper.codespaces_skus

        assert_equal(result[0], "compute_d2")
        assert_equal(result[1], "compute_d4")
        assert_equal(result[2], "compute_d8")
        assert_equal(result[3], "compute_d16")
        assert_equal(result[4], "compute_d32")
        assert_equal(result[5], "storage")
        assert_equal(result[6], "prebuild_storage")
      end
    end
  end

  context "actions methods" do
    context "#actions_monthly_usage" do
      test "returns all product usage for actions" do
        mock_list_product_usage_response(product: "actions", unit_of_measure: "Hours", quantity: 1000.0, sku_name: "linux")
        result = @client_wrapper.actions_monthly_usage
        assert_equal(result[:product_usage][0][:product][:name], "actions")
        assert_equal(result[:product_usage][0][:product_sku][:name], "linux")
        assert_equal(result[:product_usage][0][:product_sku][:unit_of_measure][:name], "Hours")
        assert_equal(result[:product_usage][0][:usage][:quantity], 1000.0)
      end
    end
  end
end
