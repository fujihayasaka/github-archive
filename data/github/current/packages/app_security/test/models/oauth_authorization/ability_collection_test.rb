# typed: true
# frozen_string_literal: true

require "test_helper"

class OauthAuthorizationAbilityCollectionTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    # The OauthAuthorization::AbilityCollection extention is used by
    # several collections of sub-resources on a User. We could use any one of them for our
    # tests. In this case, we're choosing to use the emails collection.
    @user        = create(:user)
    @collection  = @user.resources.emails
    @integration = create(:integration, default_permissions: { "emails" => :read })
  end

  test "allows an OauthAuthorization to be granted an ability on the collection" do
    access = create(:oauth_access, user: @user, application: @integration)

    assert_predicate access, :valid?
    assert @collection.grant?(access.authorization, :read)
  end

  test "does not allow anything other than an OauthAuthorization to be granted an ability on the collection" do
    user = create(:user)
    refute @collection.grant?(user, :read)
  end

  context "#permit?" do
    test "returns true if the actor is the owner of the collection" do
      assert_able @user, :read, @collection
    end

    test "returns true if the actor has permission on the collection" do
      authorization = OauthAuthorization.create(user: @user, application: @integration)
      @collection.add_actor(authorization, action: :read)

      # Check the Abilities table directly to account for fine grained
      # permissions not being created in the collab cluster in this test.
      refute_empty Ability.where(
        actor_id: authorization.ability_id,
        actor_type: authorization.ability_type,
        subject_id: @collection.ability_id,
        subject_type: @collection.ability_type,
        action: Ability.actions[:read],
        priority: Ability.priorities[:direct],
      )
    end

    test "returns false if the actor does not have direct permission to the user" do
      integration = create(:integration)
      access      = create(:oauth_access, user: @user, application: integration)

      refute_able access.authorization, :read, @collection
    end
  end
end
