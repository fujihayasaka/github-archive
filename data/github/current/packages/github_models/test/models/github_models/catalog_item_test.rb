# typed: true
# frozen_string_literal: true

require "test_helper"

class GitHubModels::CatalogItemTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @staff_user = create(:staff_admin_user)
    @static_gpt4 = GitHubModels::Types::Static::GPT4
    @gpt4_catalog_item = GitHubModels::CatalogItem.create!(key: "#{@static_gpt4[:registry]}/#{@static_gpt4[:name]}", value: {})
  end

  context "validations" do
    test "requires a non-nil key" do
      catalog_item = GitHubModels::CatalogItem.new(key: nil)
      refute_predicate catalog_item, :valid?
      assert_includes catalog_item.errors[:key], "can't be blank"
    end

    test "disallows an empty key" do
      catalog_item = GitHubModels::CatalogItem.new(key: " ")
      refute_predicate catalog_item, :valid?
      assert_includes catalog_item.errors[:key], "can't be blank"
    end

    test "requires a unique key" do
      catalog_item = GitHubModels::CatalogItem.new(key: @gpt4_catalog_item.key)
      refute_predicate catalog_item, :valid?
      assert_includes catalog_item.errors[:key], "has already been taken"
    end
  end

  context ".key_for" do
    test "returns key to represent a model with the given registry and name" do
      assert_equal "azure-openai/gpt4o", GitHubModels::CatalogItem.key_for(registry: "azure-openai", name: "gpt4o")
    end
  end

  context ".registry_and_name_from_key" do
    test "returns the registry and name from the given key" do
      registry = "azure-openai"
      name = "gpt4o"
      key = GitHubModels::CatalogItem.key_for(registry: registry, name: name)

      assert_equal [registry, name], GitHubModels::CatalogItem.registry_and_name_from_key(key)
    end

    test "returns nil when the given key is invalid" do
      registry, name = GitHubModels::CatalogItem.registry_and_name_from_key("foobar")

      assert_nil registry
      assert_nil name
    end
  end

  context "#to_model" do
    test "returns Model hash representation of catalog item" do
      catalog_item = create(:github_models_catalog_item, :gpt_4o)

      result = catalog_item.to_model

      assert_instance_of Hash, result
      assert_same_elements %i(id registry name original_name friendly_name task publisher license description summary
        model_version notes popularity tags rate_limit_tier supported_languages max_output_tokens
        max_input_tokens training_data_date logo_url dark_mode_icon light_mode_icon evaluation license_description
        supported_input_modalities supported_output_modalities), result.keys
      assert_equal "gpt-4o", result[:name]
      assert_equal "azure-openai", result[:registry]
      assert_equal "OpenAI GPT-4o", result[:friendly_name]
      assert_equal "OpenAI", result[:publisher]
    end
  end


  context "#task" do
    test "returns task from JSON value when present" do
      task = "chat-completion"
      catalog_item = GitHubModels::CatalogItem.new(value: { model: { task: task } }.to_json)
      assert_equal task, catalog_item.task
    end

    test "returns nil when 'model' is not in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: {}.to_json)
      assert_nil catalog_item.task
    end

    test "returns nil when 'task' is not in 'model' in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: { model: {} }.to_json)
      assert_nil catalog_item.task
    end
  end

  context "#name" do
    test "returns model name from JSON value when present" do
      name = "FancyNiceModelThingy"
      catalog_item = GitHubModels::CatalogItem.new(value: { model: { name: name } }.to_json)
      assert_equal name, catalog_item.name
    end

    test "returns nil when 'model' is not in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: {}.to_json)
      assert_nil catalog_item.name
    end

    test "returns nil when 'name' is not in 'model' in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: { model: {} }.to_json)
      assert_nil catalog_item.name
    end
  end

  context "#model_id" do
    test "returns model ID from JSON value when present" do
      model_id = "azureml://registries/azure-openai/models/gpt-4o/versions/2024-08-06"
      catalog_item = GitHubModels::CatalogItem.new(value: { model: { id: model_id } }.to_json)
      assert_equal model_id, catalog_item.model_id
    end

    test "returns nil when 'model' is not in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: {}.to_json)
      assert_nil catalog_item.model_id
    end

    test "returns nil when 'id' is not in 'model' in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: { model: {} }.to_json)
      assert_nil catalog_item.model_id
    end
  end

  context "#rate_limit_tier" do
    test "returns rate limit tier from JSON value when present" do
      rate_limit_tier = "high"
      catalog_item = GitHubModels::CatalogItem.new(value: { model: { rate_limit_tier: rate_limit_tier } }.to_json)
      assert_equal rate_limit_tier, catalog_item.rate_limit_tier
    end

    test "returns nil when 'model' is not in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: {}.to_json)
      assert_nil catalog_item.rate_limit_tier
    end

    test "returns nil when 'rate_limit_tier' is not in 'model' in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: { model: {} }.to_json)
      assert_nil catalog_item.rate_limit_tier
    end
  end

  context "#publisher" do
    test "returns publisher from JSON value when present" do
      publisher = "OpenAI"
      catalog_item = GitHubModels::CatalogItem.new(value: { model: { publisher: publisher } }.to_json)
      assert_equal publisher, catalog_item.publisher
    end

    test "returns nil when 'model' is not in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: {}.to_json)
      assert_nil catalog_item.publisher
    end

    test "returns nil when 'publisher' is not in 'model' in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: { model: {} }.to_json)
      assert_nil catalog_item.publisher
    end
  end

  context "#logo_url" do
    test "returns logo_url from JSON value when present" do
      logo_url = "/images/modules/marketplace/models/families/openai.svg"
      catalog_item = GitHubModels::CatalogItem.new(value: { model: { logo_url: logo_url } }.to_json)
      assert_equal logo_url, catalog_item.logo_url
    end

    test "returns nil when 'model' is not in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: {}.to_json)
      assert_nil catalog_item.logo_url
    end

    test "returns nil when 'logo_url' is not in 'model' in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: { model: {} }.to_json)
      assert_nil catalog_item.logo_url
    end
  end

  context "#icon_src" do
    test "returns dark mode icon image source when it's present and dark_mode=true" do
      catalog_item = GitHubModels::CatalogItem.new(value: { model: { dark_mode_icon: "svg123" } }.to_json)
      assert_equal "data:image/svg+xml;base64,svg123", catalog_item.icon_src(dark_mode: true)
    end

    test "returns logo URL when dark_mode=false and there is no light mode icon" do
      catalog_item = GitHubModels::CatalogItem.new(value: { model: { logo_url: "/some/path.png" } }.to_json)
      assert_equal "/some/path.png", catalog_item.icon_src(dark_mode: false)
    end

    test "returns light mode icon image source when it's present and dark_mode=false" do
      catalog_item = GitHubModels::CatalogItem.new(value: { model: { light_mode_icon: "svg123" } }.to_json)
      assert_equal "data:image/svg+xml;base64,svg123", catalog_item.icon_src(dark_mode: false)
    end

    test "returns logo URL when dark_mode=true and there is no dark mode icon" do
      catalog_item = GitHubModels::CatalogItem.new(value: { model: { logo_url: "/some/path.png" } }.to_json)
      assert_equal "/some/path.png", catalog_item.icon_src(dark_mode: true)
    end
  end

  context "#summary" do
    test "returns summary from JSON value when present" do
      summary = "OpenAI's most advanced multimodal model in the GPT-4 family. Can handle both text and image inputs."
      catalog_item = GitHubModels::CatalogItem.new(value: { model: { summary: summary } }.to_json)
      assert_equal summary, catalog_item.summary
    end

    test "returns nil when 'model' is not in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: {}.to_json)
      assert_nil catalog_item.summary
    end

    test "returns nil when 'summary' is not in 'model' in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: { model: {} }.to_json)
      assert_nil catalog_item.summary
    end
  end

  context "#notes" do
    test "returns notes from JSON value when present" do
      notes = "## Model Provider\n\nThis model is provided through the Azure OpenAI service."
      catalog_item = GitHubModels::CatalogItem.new(value: { model: { notes: notes } }.to_json)
      assert_equal notes, catalog_item.notes
    end

    test "returns nil when 'model' is not in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: {}.to_json)
      assert_nil catalog_item.notes
    end

    test "returns nil when 'notes' is not in 'model' in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: { model: {} }.to_json)
      assert_nil catalog_item.notes
    end
  end

  context "#friendly_name" do
    test "returns friendly name from JSON value when present" do
      friendly_name = "A Fancy Model for the People"
      catalog_item = GitHubModels::CatalogItem.new(value: { model: { friendly_name: friendly_name } }.to_json)
      assert_equal friendly_name, catalog_item.friendly_name
    end

    test "returns nil when 'model' is not in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: {}.to_json)
      assert_nil catalog_item.friendly_name
    end

    test "returns nil when 'friendly_name' is not in 'model' in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: { model: {} }.to_json)
      assert_nil catalog_item.friendly_name
    end
  end

  context "#supported_input_modalities" do
    test "returns supported_input_modalities from JSON value when present" do
      supported_input_modalities = %w(text image audio)
      catalog_item = GitHubModels::CatalogItem.new(value: {
        model: { supported_input_modalities: supported_input_modalities },
      }.to_json)
      assert_equal supported_input_modalities, catalog_item.supported_input_modalities
    end

    test "returns an empty list when 'model' is not in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: {}.to_json)
      assert_empty catalog_item.supported_input_modalities
    end

    test "returns an empty list when 'supported_input_modalities' is not in 'model' in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: { model: {} }.to_json)
      assert_empty catalog_item.supported_input_modalities
    end
  end

  context "#supported_output_modalities" do
    test "returns supported_output_modalities from JSON value when present" do
      supported_output_modalities = %w(text video)
      catalog_item = GitHubModels::CatalogItem.new(value: {
        model: { supported_output_modalities: supported_output_modalities },
      }.to_json)
      assert_equal supported_output_modalities, catalog_item.supported_output_modalities
    end

    test "returns an empty list when 'model' is not in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: {}.to_json)
      assert_empty catalog_item.supported_output_modalities
    end

    test "returns an empty list when 'supported_output_modalities' is not in 'model' in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: { model: {} }.to_json)
      assert_empty catalog_item.supported_output_modalities
    end
  end

  context "#tags" do
    test "returns tags from JSON value when present" do
      tags = %w(Some friendly words)
      catalog_item = GitHubModels::CatalogItem.new(value: { model: { tags: tags } }.to_json)
      assert_equal tags, catalog_item.tags
    end

    test "returns an empty list when 'model' is not in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: {}.to_json)
      assert_empty catalog_item.tags
    end

    test "returns an empty list when 'tags' is not in 'model' in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: { model: {} }.to_json)
      assert_empty catalog_item.tags
    end
  end

  context "#supported_languages" do
    test "returns supported_languages from JSON value when present" do
      supported_languages = %w(en it af)
      catalog_item = GitHubModels::CatalogItem.new(value: {
        model: { supported_languages: supported_languages },
      }.to_json)
      assert_equal supported_languages, catalog_item.supported_languages
    end

    test "returns an empty list when 'model' is not in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: {}.to_json)
      assert_empty catalog_item.supported_languages
    end

    test "returns an empty list when 'supported_languages' is not in 'model' in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: { model: {} }.to_json)
      assert_empty catalog_item.supported_languages
    end
  end

  context "#dark_mode_icon" do
    test "returns dark-mode icon from JSON value when present" do
      dark_mode_icon = "svg123"
      catalog_item = GitHubModels::CatalogItem.new(value: { model: { dark_mode_icon: dark_mode_icon } }.to_json)
      assert_equal dark_mode_icon, catalog_item.dark_mode_icon
    end

    test "returns nil when 'model' is not in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: {}.to_json)
      assert_nil catalog_item.dark_mode_icon
    end

    test "returns nil when 'dark_mode_icon' is not in 'model' in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: { model: {} }.to_json)
      assert_nil catalog_item.dark_mode_icon
    end
  end

  context "#light_mode_icon" do
    test "returns light-mode icon from JSON value when present" do
      light_mode_icon = "svg123"
      catalog_item = GitHubModels::CatalogItem.new(value: { model: { light_mode_icon: light_mode_icon } }.to_json)
      assert_equal light_mode_icon, catalog_item.light_mode_icon
    end

    test "returns nil when 'model' is not in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: {}.to_json)
      assert_nil catalog_item.light_mode_icon
    end

    test "returns nil when 'light_mode_icon' is not in 'model' in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: { model: {} }.to_json)
      assert_nil catalog_item.light_mode_icon
    end
  end

  context "#description" do
    test "returns description from JSON value when present" do
      description = "GPT-4o offers a shift in how AI models interact with multimodal inputs."
      catalog_item = GitHubModels::CatalogItem.new(value: { model: { description: description } }.to_json)
      assert_equal description, catalog_item.description
    end

    test "returns nil when 'model' is not in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: {}.to_json)
      assert_nil catalog_item.description
    end

    test "returns nil when 'description' is not in 'model' in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: { model: {} }.to_json)
      assert_nil catalog_item.description
    end
  end

  context "#registry" do
    test "returns registry from JSON value when present" do
      registry = "azure-openai"
      catalog_item = GitHubModels::CatalogItem.new(value: { model: { registry: registry } }.to_json)
      assert_equal registry, catalog_item.registry
    end

    test "returns nil when 'model' is not in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: {}.to_json)
      assert_nil catalog_item.registry
    end

    test "returns nil when 'registry' is not in 'model' in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: { model: {} }.to_json)
      assert_nil catalog_item.registry
    end
  end

  context "#max_output_tokens" do
    test "returns max_output_tokens from JSON value when present" do
      max_output_tokens = 1234
      catalog_item = GitHubModels::CatalogItem.new(value: { model: { max_output_tokens: max_output_tokens } }.to_json)
      assert_equal max_output_tokens, catalog_item.max_output_tokens
    end

    test "returns nil when 'model' is not in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: {}.to_json)
      assert_nil catalog_item.max_output_tokens
    end

    test "returns nil when 'max_output_tokens' is not in 'model' in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: { model: {} }.to_json)
      assert_nil catalog_item.max_output_tokens
    end
  end

  context "#max_input_tokens" do
    test "returns max_input_tokens from JSON value when present" do
      max_input_tokens = 1234
      catalog_item = GitHubModels::CatalogItem.new(value: { model: { max_input_tokens: max_input_tokens } }.to_json)
      assert_equal max_input_tokens, catalog_item.max_input_tokens
    end

    test "returns nil when 'model' is not in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: {}.to_json)
      assert_nil catalog_item.max_input_tokens
    end

    test "returns nil when 'max_input_tokens' is not in 'model' in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: { model: {} }.to_json)
      assert_nil catalog_item.max_input_tokens
    end
  end

  context "#details_path" do
    test "returns the Models Marketplace path for the model" do
      catalog_item = GitHubModels::CatalogItem.new(value: {
        model: { registry: "azure-openai", name: "gpt4o" },
      }.to_json)
      assert_equal "/marketplace/models/azure-openai/gpt4o", catalog_item.details_path
    end
  end

  context "#license" do
    test "returns license from JSON value when present" do
      license = "custom"
      catalog_item = GitHubModels::CatalogItem.new(value: { model: { license: license } }.to_json)
      assert_equal license, catalog_item.license
    end

    test "returns nil when 'model' is not in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: {}.to_json)
      assert_nil catalog_item.license
    end

    test "returns nil when 'license' is not in 'model' in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: { model: {} }.to_json)
      assert_nil catalog_item.license
    end
  end

  context "#license_description" do
    test "returns license description from JSON value when present" do
      license_description = "Use of Azure OpenAI Service is subject to applicable Microsoft\nProduct Terms"
      catalog_item = GitHubModels::CatalogItem.new(value: {
        model: { license_description: license_description },
      }.to_json)
      assert_equal license_description, catalog_item.license_description
    end

    test "returns nil when 'model' is not in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: {}.to_json)
      assert_nil catalog_item.license_description
    end

    test "returns nil when 'license_description' is not in 'model' in JSON value" do
      catalog_item = GitHubModels::CatalogItem.new(value: { model: {} }.to_json)
      assert_nil catalog_item.license_description
    end
  end

  context "visibility_map" do
    test "returns the correct mapping for visible models" do
      map = GitHubModels::CatalogItem.visibility_map(@user)

      assert map["#{@static_gpt4[:registry]}/#{@static_gpt4[:name]}"]
    end

    test "returns the correct mapping for hidden models" do
      @gpt4_catalog_item.hidden!
      map = GitHubModels::CatalogItem.visibility_map(@user)

      refute map["#{@static_gpt4[:registry]}/#{@static_gpt4[:name]}"]
    end

    test "returns the correct mapping for staffshipped models and staff users", skip_in_multitenant_mode: true do
      @gpt4_catalog_item.staffshipped!
      map = GitHubModels::CatalogItem.visibility_map(@staff_user)

      assert map["#{@static_gpt4[:registry]}/#{@static_gpt4[:name]}"]
    end

    test "returns the correct mapping for staffshipped models and normal users" do
      @gpt4_catalog_item.staffshipped!
      map = GitHubModels::CatalogItem.visibility_map(@user)

      refute map["#{@static_gpt4[:registry]}/#{@static_gpt4[:name]}"]
    end

    test "returns the correct mapping for staffshipped models and nil users" do
      @gpt4_catalog_item.staffshipped!
      map = GitHubModels::CatalogItem.visibility_map(nil)

      refute map["#{@static_gpt4[:registry]}/#{@static_gpt4[:name]}"]
    end
  end

  context "#value=" do
    test "clears memoized attributes" do
      catalog_item = GitHubModels::CatalogItem.new(value: { model: { name: "gpt4o" } }.to_json)
      assert_equal "gpt4o", catalog_item.name # cause the parsed_value and name to be memoized

      catalog_item.value = { model: { name: "Some Brand New Name" } }.to_json

      assert_equal "Some Brand New Name", catalog_item.name
    end
  end

  context "can_view?" do
    test "true for a visible model" do
      assert GitHubModels::CatalogItem.can_view?(user: @user, registry: @static_gpt4[:registry], name: @static_gpt4[:name])
    end

    test "false for a hidden model" do
      @gpt4_catalog_item.hidden!
      refute GitHubModels::CatalogItem.can_view?(user: @user, registry: @static_gpt4[:registry], name: @static_gpt4[:name])
    end

    test "true for a staffshipped model and staff user", skip_in_multitenant_mode: true do
      @gpt4_catalog_item.staffshipped!
      assert GitHubModels::CatalogItem.can_view?(user: @staff_user, registry: @static_gpt4[:registry], name: @static_gpt4[:name])
    end

    test "false for a staffshipped model and normal user" do
      @gpt4_catalog_item.staffshipped!
      refute GitHubModels::CatalogItem.can_view?(user: @user, registry: @static_gpt4[:registry], name: @static_gpt4[:name])
    end

    test "false for a staffshipped model and nil user" do
      @gpt4_catalog_item.staffshipped!
      refute GitHubModels::CatalogItem.can_view?(user: nil, registry: @static_gpt4[:registry], name: @static_gpt4[:name])
    end

    test "false for a bad registry/name pair" do
      refute GitHubModels::CatalogItem.can_view?(user: nil, registry: "nonsense", name: @static_gpt4[:name])
    end
  end
end unless GitHub.enterprise?
