# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationListingTest < GitHub::TestCase
  fixtures do
    @integration = create(:integration, name: "integration-HiYa")
    @listing = create :integration_listing, integration: @integration
  end

  test "updates an integration to be public" do
    integration = create(:integration, visibility: :private_visibility)
    refute_predicate integration, :public_visibility?

    listing = create(:integration_listing, integration: integration)

    listing.valid?
    assert_predicate integration, :public_visibility?
  end

  context "#name" do
    test "uses the OAuthApplication name if the column is nil" do
      assert_equal @listing.integration.name, @listing.name
    end

    test "uses the name in the listing if it exists" do
      @listing.update(name: "The Integration Name (TM)")
      assert_equal "The Integration Name (TM)", @listing.name
    end

    test "uses the OAuthApplication name if the column was blanked out" do
      @listing.update(name: "")
      assert_equal @listing.integration.name, @listing.name
    end
  end

  context "#client_id" do
    test "returns the client ID for the associated OAuth application" do
      assert_equal @listing.integration.key, @listing.client_id
    end
  end

  context "#slug" do
    test "only sets the slug if it isn't already set" do
      listing = build(:integration_listing, integration: create(:oauth_application))
      listing.slug = "the-exact-slug"
      listing.save!
      assert_equal "the-exact-slug", listing.slug
    end

    test "sets the slug if the slug is blank" do
      listing = build(:integration_listing, integration: create(:oauth_application))
      listing.slug = ""
      listing.save
      assert listing.errors.empty?
    end

    test "blacklisted slugs are invalid" do
      listing = build(:integration_listing, slug: "categories")
      refute listing.valid?
      assert listing.errors[:slug]
    end

    test "slugs containing emojis are invalid" do
      listing = build(:integration_listing, slug: "🐹")
      refute listing.valid?
      assert listing.errors[:slug]
    end

    test "duplicate slugs are not allowed" do
      listing1 = build(:integration_listing, slug: @listing.slug)
      refute listing1.valid?
      assert listing1.errors[:slug].include? "has already been taken"
    end

    test "is based on name" do
      integration = create(:oauth_application, name: "A beautiful integration")
      listing = create(:integration_listing, integration: integration, slug: nil)
      assert_equal "A beautiful integration", listing.name
      assert_equal "a-beautiful-integration", listing.slug
    end
  end

  context "#state" do
    test "defaults to prerelease" do
      assert_predicate @listing, :draft?
    end

    test "can be moved to public" do
      assert_predicate @listing, :draft?
      @listing.state = :published
      assert_predicate @listing, :published?
    end
  end

  context "#body" do
    test "content can be Markdown" do
      @listing.body = "**Testing** the _content_."

      assert_equal "<p><strong>Testing</strong> the <em>content</em>.</p>", @listing.body_html
    end

    test "content uses the IntegrationListingPipeline (not GitHub Flavored)" do
      @listing.body = "- [ ] Tasks aren't expanded"

      assert_equal "<ul>\n<li>[ ] Tasks aren't expanded</li>\n</ul>", @listing.body_html,
        "The pipeline should not allow for GitHub Flavored Markdown"
    end
  end

  context "#draft?" do
    test "listing is draft if state is draft" do
      @listing.state = :draft
      assert @listing.draft?
    end

    test "listing is not a draft if published" do
      @listing.state = :published
      refute @listing.draft?
    end
  end

  context "validates :has_one_redirection_url" do
    test "a listing must have either a `learn_more_url` or `installation_url`" do
      @listing.learn_more_url = @listing.installation_url = nil
      @listing.valid?
      assert_match /either an installation URL or a learn more URL/, @listing.errors[:base].first
    end
  end

  context "#integrations_two_listing?" do
    test "returns false for an Oauth integration listing" do
      listing = build(:integration_listing, integration: create(:oauth_application))
      refute_predicate listing, :integrations_two_listing?
    end

    test "returns true for an integration listing" do
      listing = build(:integration_listing, integration: create(:integration))
      assert_predicate listing, :integrations_two_listing?
    end
  end
end
