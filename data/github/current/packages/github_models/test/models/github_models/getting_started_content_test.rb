# typed: true
# frozen_string_literal: true

require "test_helper"

class GitHubModels::GettingStartedContentTest < GitHub::TestCase

  test "model capabilities" do
    catalog_item = create(:github_models_catalog_item, :gpt_4o)

    capabilities = GitHubModels::GettingStartedContent.get_model_capabilities(catalog_item.to_model, catalog_item.to_schema)

    assert capabilities[:top_p]
    assert capabilities[:max_tokens]
    assert capabilities[:temperature]
    assert capabilities[:system_prompt]
  end
end
