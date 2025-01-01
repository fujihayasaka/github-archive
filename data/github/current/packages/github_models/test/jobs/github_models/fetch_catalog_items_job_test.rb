# typed: true
# frozen_string_literal: true

require "test_helper"

class GitHubModels::FetchCatalogItemsJobTest < GitHub::TestCase
  setup do
    @mock_azure_model_gpt4 = GitHubModels::Types::Static::GPT4
    @mock_azure_model_gpt4o = GitHubModels::Types::Static::GPT4o
    @mock_azure_model_schema_gpt4 = GitHubModels::Types::Static::GPT4_SCHEMA
    @mock_azure_model_schema_gpt4o = GitHubModels::Types::Static::GPT4o_SCHEMA
    @mock_azure_models_response = [@mock_azure_model_gpt4, @mock_azure_model_gpt4o]

    GitHubModels::Client.stubs(:fetch_models).returns(@mock_azure_models_response)

    GitHubModels::Client.stubs(:fetch_model_details)
      .with(
        registry: @mock_azure_model_gpt4o[:registry],
        model: @mock_azure_model_gpt4o[:name],
        version: @mock_azure_model_gpt4o[:model_version])
      .returns(@mock_azure_model_gpt4o)

    GitHubModels::Client.stubs(:fetch_model_details)
      .with(
        registry: @mock_azure_model_gpt4[:registry],
        model: @mock_azure_model_gpt4[:name],
        version: @mock_azure_model_gpt4[:model_version])
      .returns(@mock_azure_model_gpt4)

    GitHubModels::Client.stubs(:fetch_model_schema)
      .with(registry: @mock_azure_model_gpt4[:registry], model: @mock_azure_model_gpt4[:name])
      .returns(@mock_azure_model_schema_gpt4)

    GitHubModels::Client.stubs(:fetch_model_schema)
      .with(registry: @mock_azure_model_gpt4o[:registry], model: @mock_azure_model_gpt4o[:name])
      .returns(@mock_azure_model_schema_gpt4o)

    GitHubModels::Client.stubs(:fetch_publishers)
      .with
      .returns({ "value" => [{
        "publisherName" => "OpenAI",
        "iconLight" => "aBase64string"
      }] })

    GitHubModels::Payloads::GettingStartedContent.stubs(:fetch).returns({ content: "content" })
    enable_feature_flag(:project_neutron_fetch_catalog_items_job)
  end

  test "creates or updates Azure catalog data" do
    assert_difference("GitHubModels::CatalogItem.count", 2) do
      GitHubModels::FetchCatalogItemsJob.perform_now
    end

    gpt4_catalog_item = GitHubModels::CatalogItem.find_by!(key: "#{@mock_azure_model_gpt4[:registry]}/" \
      "#{@mock_azure_model_gpt4[:name]}")
    assert_equal JSON.parse(@mock_azure_model_schema_gpt4.to_json), JSON.parse(gpt4_catalog_item.value)["schema"]
    assert_equal JSON.parse(@mock_azure_model_gpt4.to_json), JSON.parse(gpt4_catalog_item.value)["model"]
    assert_equal 0, gpt4_catalog_item.popularity
    assert_equal "gpt-4", gpt4_catalog_item.name
    assert_equal "gpt-4", gpt4_catalog_item.original_name
    assert_equal "gpt-4", gpt4_catalog_item.friendly_name
    assert_equal Date.new(2023, 10, 1), gpt4_catalog_item.training_data_date
    assert_equal "azure_openai", gpt4_catalog_item.source
    assert_equal "chat-completion", gpt4_catalog_item.task
    assert_equal "", gpt4_catalog_item.license
    assert_equal "This description is artificially short", gpt4_catalog_item.description
    assert_equal "What you need to know", gpt4_catalog_item.summary
    assert_equal "OpenAI", gpt4_catalog_item.publisher
    assert_equal "5", gpt4_catalog_item.model_version
    assert_equal "", gpt4_catalog_item.notes
    assert_equal [], gpt4_catalog_item.tags
    assert_equal "high", gpt4_catalog_item.rate_limit_tier
    assert_equal ["English"], gpt4_catalog_item.supported_languages
    assert_equal 4096, gpt4_catalog_item.max_output_tokens
    assert_equal 131072, gpt4_catalog_item.max_input_tokens
    assert_equal "", gpt4_catalog_item.evaluation
    assert_equal "", gpt4_catalog_item.license_description
    assert_equal %w[text image audio], gpt4_catalog_item.supported_input_modalities
    assert_equal ["text"], gpt4_catalog_item.supported_output_modalities

    gpt4o_catalog_item = GitHubModels::CatalogItem.find_by!(key: "#{@mock_azure_model_gpt4o[:registry]}/" \
      "#{@mock_azure_model_gpt4o[:name]}")
    assert_equal JSON.parse(@mock_azure_model_schema_gpt4o.to_json), JSON.parse(gpt4o_catalog_item.value)["schema"]
    assert_equal JSON.parse(@mock_azure_model_gpt4o.to_json), JSON.parse(gpt4o_catalog_item.value)["model"]
    assert_equal 54.98, gpt4o_catalog_item.popularity

    assert_no_difference("GitHubModels::CatalogItem.count") do
      GitHubModels::FetchCatalogItemsJob.perform_now
    end
  end

  test "adds Publisher records" do
    assert_difference("GitHubModels::Publisher.count", 1) do
      GitHubModels::FetchCatalogItemsJob.perform_now
    end

    publisher = T.must(GitHubModels::Publisher.first)
    assert_equal "OpenAI", publisher.name
    assert_equal "/images/modules/marketplace/models/families/openai.svg", publisher.logo_url
    assert_equal "aBase64string", publisher.light_mode_icon
  end

  test "only adds Publisher records if names are case-insensentive different, still updates other values" do
    publisher = create(:github_models_publisher, name: "OPENAI", light_mode_icon: "iconMuyFea")

    assert_no_difference("GitHubModels::Publisher.count") do
      GitHubModels::FetchCatalogItemsJob.perform_now
    end

    assert_equal "aBase64string", publisher.reload.light_mode_icon
  end

  test "associates CatalogItems and their Publisher" do
    create(:github_models_publisher, name: "OpenAI")

    assert_difference("GitHubModels::CatalogItem.where.not(github_models_publisher_id: nil).count", 2) do
      GitHubModels::FetchCatalogItemsJob.perform_now
    end
  end

  test "errors when a CatalogItems doesn't get Publisher associated" do
    GitHubModels::Client.stubs(:fetch_publishers).with
    .returns({ "value" => [{ "publisherName" => "Weird outlier publisher", }] })


    GitHub.logger.expects(:error).once.with("Catalog Item has no matching publisher", github_models_catalog_item_name: "gpt-4o")
    GitHub.logger.expects(:error).once.with("Catalog Item has no matching publisher", github_models_catalog_item_name: "gpt-4")

    GitHubModels::FetchCatalogItemsJob.perform_now
  end

  test "removes Azure catalog data that doesn't exist in the index" do
    model_to_delete = create(:github_models_catalog_item, key: "not/real")

    assert_equal 1, GitHubModels::CatalogItem.count

    GitHubModels::FetchCatalogItemsJob.perform_now

    assert_enqueued_with(job: RemoveFromSearchIndexJob, args: ["azure_model", model_to_delete.id])
    assert_enqueued_with(job: AddToSearchIndexJob)
    assert_enqueued_with(job: AddToSearchIndexJob)

    assert_equal 2, GitHubModels::CatalogItem.count

    assert_raises ActiveRecord::RecordNotFound do
      model_to_delete.reload
    end
  end

  test "is resilient to network failures" do
    assert_equal 0, GitHubModels::CatalogItem.count

    GitHubModels::Client.expects(:fetch_model_details)
      .with(
        registry: @mock_azure_model_gpt4[:registry],
        model: @mock_azure_model_gpt4[:name],
        version: @mock_azure_model_gpt4[:model_version])
      .raises(GitHubModels::Client::ApiError.new("kaboom!"))

    GitHub.logger.expects(:error).with("Skipping over model", anything)
    GitHub.logger.expects(:error).at_most_once.with(
      "Catalog Item has no matching publisher",
      github_models_catalog_item_name: "gpt-4o")


    GitHubModels::FetchCatalogItemsJob.perform_now
    assert_equal 1, GitHubModels::CatalogItem.count

    # Assert that GPT-4 entry does not exist
    refute GitHubModels::CatalogItem.exists?(key: "#{@mock_azure_model_gpt4[:registry]}/" \
      "#{@mock_azure_model_gpt4[:name]}")

    # Assert that GPT-4o entry, which comes after GPT-4 in @mock_azure_models_response, exists
    assert GitHubModels::CatalogItem.exists?(key: "#{@mock_azure_model_gpt4o[:registry]}/" \
      "#{@mock_azure_model_gpt4o[:name]}")
  end

  test "does nothing if the flag is disabled" do
    disable_feature_flag(:project_neutron_fetch_catalog_items_job)
    assert_equal 0, GitHubModels::CatalogItem.count

    assert_no_changes -> { GitHubModels::CatalogItem.count } do
      GitHubModels::FetchCatalogItemsJob.perform_now
    end
  end

  context "getting started content" do
    test "filter on existing getting started content if feature disabled" do
      disable_feature_flag(:github_models_fetch_catalog_items_job_no_content_filter)

      GitHubModels::Payloads::GettingStartedContent.expects(:fetch).once.returns({ content: "content" })

      GitHubModels::FetchCatalogItemsJob.perform_now
    end

    test "skips filter on existing getting started content if feature enabled" do
      enable_feature_flag(:github_models_fetch_catalog_items_job_no_content_filter)

      GitHubModels::Payloads::GettingStartedContent.expects(:fetch).never

      GitHubModels::FetchCatalogItemsJob.perform_now
    end
  end
end
