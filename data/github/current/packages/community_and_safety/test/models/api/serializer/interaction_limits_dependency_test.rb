# typed: false
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class InteractionLimitsSerializersTest < Api::SerializerTestCase
  fixtures do
    @repo = create(:repository)
    @user = @repo.owner
    @org = create(:organization)
  end

  context "#interaction_ability_hash" do
    test "payload is valid with interaction restrictions set for repository" do
      repo_interactions = RepositoryInteractionAbility.new(@repo)
      assert repo_interactions.set_ability(:contributors_only, @user)

      output = interaction_ability(@repo)
      assert_same_elements %w[limit origin expires_at], output.keys
      assert_equal "repository", output["origin"]
    end

    test "payload is valid with interaction restrictions set for org" do
      org_interactions = RepositoryInteractionAbility.new(@org)
      repo_interactions = RepositoryInteractionAbility.new(@repo)
      assert repo_interactions.set_ability(:contributors_only, @user)
      assert org_interactions.set_ability(:contributors_only, @org.admin)

      output = interaction_ability(@org)
      assert_same_elements %w[limit origin expires_at], output.keys
      assert_equal "organization", output["origin"]
    end

    test "payload is valid with interaction restrictions set for user" do
      user_interactions = RepositoryInteractionAbility.new(@user)
      assert user_interactions.set_ability(:contributors_only, @user)

      output = interaction_ability(@user)
      assert_same_elements %w[limit origin expires_at], output.keys
      assert_equal "user", output["origin"]
    end

    test "returns existing_users instead of sockpuppet_disallowed" do
      repo_interactions = RepositoryInteractionAbility.new(@repo)
      assert repo_interactions.set_ability(:contributors_only, @user)
      assert repo_interactions.set_ability(:sockpuppet_disallowed, @user)

      output = interaction_ability(@repo)
      assert_equal "existing_users", output["limit"]
    end

    test "returns no data with no restrictions set for repository" do
      repo_interactions = RepositoryInteractionAbility.new(@repo)
      assert repo_interactions.set_ability(:contributors_only, @user)
      assert repo_interactions.set_ability(:no_limit, @user)
      output = interaction_ability(@repo)
      assert_empty output
    end

    test "returns no data with no restrictions set for org" do
      org_interactions = RepositoryInteractionAbility.new(@org)
      assert org_interactions.set_ability(:no_limit, @org.admin)
      output = interaction_ability(@org)
      assert_empty output
    end

    test "returns no data with no restrictions set for user" do
      user_interactions = RepositoryInteractionAbility.new(@user)
      assert user_interactions.set_ability(:contributors_only, @user)
      assert user_interactions.set_ability(:no_limit, @user)
      output = interaction_ability(@user)
      assert_empty output
    end
  end
end
