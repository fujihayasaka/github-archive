# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationFeatureTest < GitHub::TestCase
  fixtures do
    @feature = create :integration_feature
  end

  context "#generate_slug" do
    test "generates a URL friendly slug from the feature name" do
      feature = build(:integration_feature,
        name: "Continuously-Integrate! Today.",
        slug: nil,
      )
      assert feature.slug.blank?
      feature.save!
      assert_equal "continuously-integrate-today", feature.slug
    end

    test "updates the slug if the name is updated" do
      original_slug = @feature.slug
      @feature.save!
      assert_equal original_slug, @feature.slug
      @feature.update(name: "A New Name")
      assert_equal "a-new-name", @feature.slug
    end

    test "name must not contain emojis" do
      original_slug = @feature.slug
      @feature.save!
      assert_equal original_slug, @feature.slug
      @feature.update(name: "🐹")
      refute @feature.valid?
      assert_predicate @feature.errors[:name], :any?
    end
  end

  context "#body" do
    test "content can be Markdown" do
      @feature.body = "**Testing** the _content_."

      assert_equal "<p><strong>Testing</strong> the <em>content</em>.</p>", @feature.body_html
    end

    test "content uses the IntegrationListingPipeline (not GitHub Flavored)" do
      @feature.body = "- [ ] Tasks aren't expanded"

      assert_equal "<ul>\n<li>[ ] Tasks aren't expanded</li>\n</ul>", @feature.body_html,
        "The pipeline should not allow for GitHub Flavored Markdown"
    end
  end

  context "#ordered" do
    test "returns features ordered by name" do
      IntegrationFeature.delete_all
      feature_s = create(:integration_feature, name: "Super stuff")
      feature_a = create(:integration_feature, name: "Amazing stuff")

      expected = [feature_a, feature_s]
      assert_equal expected, IntegrationFeature.ordered
    end
  end

  context "#visible?" do
    test "returns true when state is visible" do
      @feature.state = :visible
      assert @feature.visible?
    end

    test "returns true when state is filterable" do
      @feature.state = :filterable
      assert @feature.visible?
    end

    test "returns false when state is anything else" do
      @feature.state = :draft
      refute @feature.visible?
    end
  end

  context ".not_visible" do
    test "displays integration_features set to draft or hidden" do
      hidden_feature = create(:integration_feature, state: :hidden)
      draft_feature = create(:integration_feature, state: :draft)
      create(:integration_feature, state: :visible)
      create(:integration_feature, state: :filterable)

      assert_equal IntegrationFeature.not_visible.pluck(:id).sort,
        [hidden_feature.id, draft_feature.id].sort
    end
  end
end
