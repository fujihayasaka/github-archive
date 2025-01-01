# typed: true
# frozen_string_literal: true

require "test_helper"

class AzureModels::FetchCatalogItemsJobTest < GitHub::TestCase

  setup do
    @mock_azure_model_gpt4 = Marketplace::Types::AzureModels::Static::GPT4
    @mock_azure_model_gpt4o = Marketplace::Types::AzureModels::Static::GPT4o
    @mock_azure_model_schema_gpt4 = Marketplace::Types::AzureModels::Static::GPT4_SCHEMA
    @mock_azure_model_schema_gpt4o = Marketplace::Types::AzureModels::Static::GPT4o_SCHEMA
    @mock_azure_models_response = [@mock_azure_model_gpt4, @mock_azure_model_gpt4o]

    AzureModels::Client.stubs(:fetch_model_details)
      .with(registry: @mock_azure_model_gpt4o[:registry], model: @mock_azure_model_gpt4o[:name])
      .returns(@mock_azure_model_gpt4o)

    AzureModels::Client.stubs(:fetch_model_details)
      .with(registry: @mock_azure_model_gpt4[:registry], model: @mock_azure_model_gpt4[:name])
      .returns(@mock_azure_model_gpt4)

    AzureModels::Client.stubs(:fetch_model_schema)
      .with(registry: @mock_azure_model_gpt4[:registry], model: @mock_azure_model_gpt4[:name])
      .returns(@mock_azure_model_schema_gpt4)

    AzureModels::Client.stubs(:fetch_model_schema)
      .with(registry: @mock_azure_model_gpt4o[:registry], model: @mock_azure_model_gpt4o[:name])
      .returns(@mock_azure_model_schema_gpt4o)

    AzureModels::Client.stubs(:fetch_models).returns(@mock_azure_models_response)
    AzureModels::Client.stubs(:fetch_models_v2).returns(@mock_azure_models_response)
    Marketplace::Payloads::Models::GettingStartedContent.stubs(:fetch).returns({ content: "content" })
  end

  test "creates or updates Azure catalog data" do
    assert_equal 0, AzureModels::CatalogItem.count

    AzureModels::FetchCatalogItemsJob.perform_now
    assert_equal 3, AzureModels::CatalogItem.count

    assert_equal 1, AzureModels::CatalogItem.where(key: "all_models").count

    assert_equal @mock_azure_models_response.to_json, AzureModels::CatalogItem.find_by!(key: "all_models").value

    assert_equal JSON.parse(@mock_azure_model_schema_gpt4.to_json), JSON.parse(AzureModels::CatalogItem.find_by!(key: "#{@mock_azure_model_gpt4[:registry]}/#{@mock_azure_model_gpt4[:name]}").value)["schema"]
    assert_equal JSON.parse(@mock_azure_model_gpt4.to_json), JSON.parse(AzureModels::CatalogItem.find_by!(key: "#{@mock_azure_model_gpt4[:registry]}/#{@mock_azure_model_gpt4[:name]}").value)["model"]

    assert_equal JSON.parse(@mock_azure_model_schema_gpt4o.to_json), JSON.parse(AzureModels::CatalogItem.find_by!(key: "#{@mock_azure_model_gpt4o[:registry]}/#{@mock_azure_model_gpt4o[:name]}").value)["schema"]
    assert_equal JSON.parse(@mock_azure_model_gpt4o.to_json), JSON.parse(AzureModels::CatalogItem.find_by!(key: "#{@mock_azure_model_gpt4o[:registry]}/#{@mock_azure_model_gpt4o[:name]}").value)["model"]

    AzureModels::FetchCatalogItemsJob.perform_now
    assert_equal 3, AzureModels::CatalogItem.count
  end

  test "removes Azure catalog data that doesn't exist in the index" do
    model_to_delete = AzureModels::CatalogItem.create(key: "not/real", value: "")

    assert_equal 1, AzureModels::CatalogItem.count

    AzureModels::FetchCatalogItemsJob.perform_now

    assert_enqueued_with(job: RemoveFromSearchIndexJob, args: ["azure_model", model_to_delete.id])
    assert_enqueued_with(job: AddToSearchIndexJob)
    assert_enqueued_with(job: AddToSearchIndexJob)

    assert_equal 3, AzureModels::CatalogItem.count

    assert_equal 1, AzureModels::CatalogItem.where(key: "all_models").count

    assert_raises ActiveRecord::RecordNotFound do
      model_to_delete.reload
    end
  end

  test "is resilient to network failures" do
    assert_equal 0, AzureModels::CatalogItem.count
    AzureModels::Client.expects(:fetch_model_details)
      .with(registry: @mock_azure_model_gpt4[:registry], model: @mock_azure_model_gpt4[:name])
      .raises(AzureModels::Client::ApiError.new("kaboom!"))

    # This should contain two records: `all_models` and GPT-4o
    AzureModels::FetchCatalogItemsJob.perform_now
    assert_equal 2, AzureModels::CatalogItem.count

    # Assert that the `all_models` record exists
    assert AzureModels::CatalogItem.find_by!(key: "all_models")

    # Assert that GPT-4 entry does not exist
    refute AzureModels::CatalogItem.find_by(key: "#{@mock_azure_model_gpt4[:registry]}/#{@mock_azure_model_gpt4[:name]}")

    # Assert that GPT-4o entry, which comes after GPT-4 in @mock_azure_models_response, exists
    assert AzureModels::CatalogItem.find_by!(key: "#{@mock_azure_model_gpt4o[:registry]}/#{@mock_azure_model_gpt4o[:name]}")
  end
end
