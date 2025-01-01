# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationAliasTest < GitHub::TestCase
  fixtures do
    GitHub.flipper[:owner_scoped_github_apps].disable
    @integration = create(:integration, name: "hubot-the-second-coming")
    @subject     = @integration.alias
  end

  context "with owner_scoped_github_apps flipper" do
    test "is not persisted" do
      GitHub.flipper[:owner_scoped_github_apps].enable
      integration = create(:integration, name: "hubot-the-third-coming")
      integration.reload

      assert_nil integration.alias
      GitHub.flipper[:owner_scoped_github_apps].disable
    end
  end

  context "validation" do
    context "presence" do
      test "requires a integration" do
        @subject.integration = nil

        refute_predicate @subject, :valid?
        assert_same_elements ["must exist"], @subject.errors[:integration]
      end

      test "requires a slug" do
        @subject.slug = nil

        refute_predicate @subject, :valid?
        assert_same_elements ["can't be blank"], @subject.errors[:slug]
      end

      test "rejects a slug containing emoji" do
        @subject.slug = "🐹"

        refute_predicate @subject, :valid?
        assert_same_elements ["doesn't accept 4-byte Unicode"], @subject.errors[:slug]
      end
    end

    context "uniqueness" do
      test "requires a unique integration" do
        integration_alias = create(:integration).alias
        assert_predicate integration_alias, :valid?

        integration_alias.integration = @subject.integration

        refute_predicate integration_alias, :valid?
        assert_same_elements ["has already been taken"], integration_alias.errors[:integration_id]
      end

      test "requires a unique slug" do
        integration_alias = create(:integration).alias
        assert_predicate integration_alias, :valid?

        integration_alias.slug = @subject.slug
        refute_predicate integration_alias, :valid?
        assert_same_elements ["has already been taken"], integration_alias.errors[:slug]

        integration_alias.slug = @subject.slug.upcase
        refute_predicate integration_alias, :valid?
        assert_same_elements ["has already been taken"], integration_alias.errors[:slug]
      end
    end
  end
end
