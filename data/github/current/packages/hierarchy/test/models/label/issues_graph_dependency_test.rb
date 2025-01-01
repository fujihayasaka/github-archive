# typed: true
# frozen_string_literal: true

require "test_helper"

class Label::IssuesGraphDependencyTest < GitHub::TestCase
  fixtures do
    @label = create(:label)
  end

  context "to_hierarchy" do
    test "_model_key creates a hierarchy key" do
      key = @label.to_hierarchy_model_key

      assert_equal @label.id, key[:itemId]
      assert_equal @label.repository.owner_id, key[:ownerId]
    end

    test "_model creates a hierarchy model" do
      model = @label.to_hierarchy_model

      assert_equal @label.name, model[:name]
      assert_equal @label.color, model[:color]
      assert_equal @label.name_html, model[:nameHtml]
      assert_equal @label.url, model[:url]

      key = model[:key]

      puts key.inspect
      puts @label.inspect
      assert_equal @label.id, key[:itemId]
      assert_equal @label.repository.owner_id, key[:ownerId]
    end

    test "_model_key_v2 creates a hierarchy key" do
      expected_model = {
        ownerId: @label.repository.owner_id,
        itemId: @label.id,
      }

      assert_equal expected_model, @label.to_hierarchy_model_key
    end

    test "_model_v2 creates a hierarchy model" do
      expected_model = {
        key: @label.to_hierarchy_model_key,
        name: @label.name,
        nameHtml: "#{@label.name_html}",
        url: @label.url,
        color: @label.color,
        repoId: @label.repository_id,
      }

      assert_equal expected_model, @label.to_hierarchy_model
    end
  end
end
