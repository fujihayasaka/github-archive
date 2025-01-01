# typed: false
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

module ScimSerializerShared
  include AuthenticationHelpers::SCIM

  def enterprise_slug
    if @enterprise.enterprise_server_scim_enabled?
      ""
    else
      "/enterprises/#{@enterprise.slug}"
    end
  end

  def create_identity(group_name: nil)
    user_data = Platform::Provisioning::ScimUserData.new(
      [
        { "name" => "userName", "value" => Sham.email },
        { "name" => "externalId", "value" => Sham.sha },
        { "name" => "displayName", "value" => "#{Faker::Name.first_name} #{Faker::Name.last_name}" },
        { "name" => "name.givenName", "value" => Faker::Name.first_name },
        { "name" => "name.familyName", "value" => Faker::Name.last_name },
        { "name" => "name.formatted", "value" => "#{Faker::Name.first_name} #{Faker::Name.last_name}" },
        { "name" => "emails", "value" => Sham.email },
        { "name" => "roles", "value" => "Owner" },
        { "name" => "active", "value" => "true" }
      ],
    )

    user_data.append("groups", group_name) if group_name

    create(:external_identity, provider: @enterprise.saml_provider, user: @user, scim_user_data: user_data)
  end

  def create_expected_attributes(identity, group_name: nil)
    expected_attributes = {
      "schemas" => ["urn:ietf:params:scim:schemas:core:2.0:User"],
      "id" => identity.guid,
      "externalId" => identity.scim_user_data.external_id,
      "userName" => identity.scim_user_data.user_name,
      "displayName" => identity.scim_user_data.display_name,
      "name" => {
        "givenName" => identity.scim_user_data.given_name,
        "familyName" => identity.scim_user_data.family_name,
        "formatted" => identity.scim_user_data.fetch("name.formatted", {})["value"]
      },
      "emails" => [
        { "value" => identity.scim_user_data.emails.first },
      ],
      "roles" => [
        { "value" => "Owner" },
      ],
      "active" => true,
      "meta" => {
        "resourceType" => "User",
        "created" => identity.created_at.iso8601(3),
        "lastModified" => identity.updated_at.iso8601(3),
        "location" => "#{GitHub.api_url}/scim/v2#{enterprise_slug}/Users/#{identity.guid}",
      },
    }

    expected_attributes["groups"] = []
    expected_attributes["groups"] = [{ "value" => group_name }] if group_name

    expected_attributes
  end

  def create_external_group
    external_group = ExternalGroup.new(provider: @provider)
    external_group.external_id = "4c31ae02-d538-4921-992c-d79651226a99"
    external_group.display_name = "Existing Group"
    external_group.external_id_attr = "externalId"
    external_group.save

    external_group
  end

  def create_identities
    external_identities = []

    # crate number of users and external identities
    (1..2).each do |n|
      # SCIM external identity
      scim_user_name = "user-#{n}"
      scim_display_name = "User Number #{n}"
      if GitHub.enterprise?
        scim_user = User.create_with_random_password(scim_user_name, false, { "email" => "user.number.#{n}@parks.pawnee.in.gov" })
      else
        scim_user = User.create_with_random_password(scim_user_name, false,
          { "email" => "user.number.#{n}@parks.pawnee.in.gov", "force_enterprise_managed" => true, "login_suffix" => @enterprise.shortcode })
      end
      scim_user.save!

      scim_external_id = "4c31ae02-d538-4921-992c-d79651226a" + ("%02d" % n)
      scim_user_data = scim_user_data(
        user_name: scim_user_name,
        external_id: scim_external_id,
        emails: scim_user.email,
        display_name: scim_display_name
      )

      scim_external_identity = create :external_identity,
        provider: @provider,
        scim_user_data: scim_user_data,
        user: scim_user

      profile = scim_user.create_profile
      profile.email = scim_user.email
      profile.name = scim_external_identity.display_name || "Mona #{SecureRandom.hex(8)}"
      profile.save!

      external_identities.push(scim_external_identity)
      @enterprise.add_user_accounts([scim_user.id]) unless GitHub.enterprise?
    end

    external_identities
  end
end

module ScimSerializerSharedTests
  include ScimSerializerShared

  def test_enterprise_scim_identity_hash_returns_nil_unless_passed_an_identity
    assert_nil enterprise_scim_identity
  end

  def test_enterprise_scim_identity_hash_returns_a_hash_of_attributes_related_to_the_identity
    assert_equal @expected_attributes, enterprise_scim_identity(@identity)
    assert @serializer.serialize(:enterprise_scim_identity_hash, @identity)["active"]
  end

  def test_enterprise_scim_identity_hash_returns_a_false_value_for_the_active_attribute_when_set
    identity = create(:external_identity, provider: @enterprise.saml_provider, user: @user, scim_user_data:
      Platform::Provisioning::ScimUserData.new(
        [
          { "name" => "userName", "value" => Sham.email },
          { "name" => "externalId", "value" => Sham.sha },
          { "name" => "active", "value" => "false" },
        ],
      )
    )

    refute_predicate identity.scim_user_data, :active?
    refute enterprise_scim_identity(identity)["active"]
  end

  def test_enterprise_group_hash_returns_nil_unless_passed_an_identity
    assert_nil enterprise_group
  end
end

module ScimSerializerGroupSharedTests
  include ScimSerializerShared

  def test_enterprise_scim_identity_hash_returns_a_hash_of_attributes_related_to_the_identity_with_groups
    identity = @external_identities.first

    membership = ExternalIdentityGroupMembership.new
    membership.external_group_id = @external_group.id
    membership.external_identity_id = identity.id
    membership.save

    expected_attributes = [
      {
        "value" => membership.external_group.guid,
        "$ref" => "#{GitHub.api_url}/scim/v2#{enterprise_slug}/Groups/#{ membership.external_group.guid }",
        "display" => membership.external_group.display_name,
      }
    ]

    assert_same_elements expected_attributes, @serializer.serialize(:enterprise_scim_identity_hash, identity)["groups"]
  end

  def test_enterprise_scim_identity_hash_returns_a_hash_of_attributes_related_to_the_identity_without_groups_when_excluded
    identity = @external_identities.first

    membership = ExternalIdentityGroupMembership.new
    membership.external_group_id = @external_group.id
    membership.external_identity_id = identity.id
    membership.save

    attributes_hash = enterprise_scim_identity identity,
      { excluded_attributes: "groups" }

    assert_nil attributes_hash["groups"]
  end

  def test_enterprise_scim_group_hash_returns_nil_unless_passed_a_group
    assert_nil enterprise_scim_group
  end

  def test_enterprise_scim_group_hash_returns_a_hash_of_attributes_for_the_group_no_members
    attributes_hash = enterprise_scim_group @external_group

    assert_equal ["urn:ietf:params:scim:schemas:core:2.0:Group"], attributes_hash["schemas"]
    assert_equal @external_group.guid, attributes_hash["id"]
    assert_equal @external_group.external_id, attributes_hash["externalId"]
    assert_equal @external_group.display_name, attributes_hash["displayName"]
    assert_predicate attributes_hash["members"], :empty?
  end

  def test_enterprise_scim_group_hash_returns_a_hash_of_attributes_for_the_group_with_members
    url_root = if GitHub.enterprise?
      "https://github.com/api/v3"
    else
      "https://api.github.com"
    end

    expected_members = []

    @external_identities.each do |identity|
      membership = ExternalIdentityGroupMembership.new
      membership.external_group_id = @external_group.id
      membership.external_identity_id = identity.id
      membership.save

      expected_members.push(
        {
          "value" => identity.guid,
          "$ref" => "#{url_root}/scim/v2#{enterprise_slug}/Users/#{identity.guid}",
          "display" => identity.scim_user_data.display_name,
        }
      )
    end

    attributes_hash = enterprise_scim_group @external_group

    assert_equal ["urn:ietf:params:scim:schemas:core:2.0:Group"], attributes_hash["schemas"]
    assert_equal @external_group.guid, attributes_hash["id"]
    assert_equal @external_group.external_id, attributes_hash["externalId"]
    assert_equal @external_group.display_name, attributes_hash["displayName"]
    refute_predicate attributes_hash["members"], :empty?
    assert_same_elements expected_members, attributes_hash["members"]
  end

  def test_enterprise_scim_group_hash_returns_a_hash_of_attributes_for_the_group_with_members_removed
    @external_identities.each do |identity|
      membership = ExternalIdentityGroupMembership.new
      membership.external_group_id = @external_group.id
      membership.external_identity_id = identity.id
      membership.save
    end

    attributes_hash = enterprise_scim_group @external_group,
      { excluded_attributes: "members" }

    assert_equal ["urn:ietf:params:scim:schemas:core:2.0:Group"], attributes_hash["schemas"]
    assert_equal @external_group.guid, attributes_hash["id"]
    assert_equal @external_group.external_id, attributes_hash["externalId"]
    assert_equal @external_group.display_name, attributes_hash["displayName"]
    assert_nil attributes_hash["members"]
  end

  def test_enterprise_scim_groups_hash_returns_empty_result_set_if_given_empty_array
    paginated_groups = SCIM::ResultsCollection.new \
      resources: ExternalGroup.none,
      total_results: 0,
      start_index: 1

    expected_results = { "schemas" => ["urn:ietf:params:scim:api:messages:2.0:ListResponse"],
      "totalResults" => 0,
      "itemsPerPage" => 0,
      "startIndex" => 1,
      "Resources" => [],
    }
    assert_equal expected_results, enterprise_scim_groups(paginated_groups)
  end

  def test_enterprise_scim_groups_hash_returns_a_not_empty_result_for_an_array
    paginated_groups = SCIM::ResultsCollection.new \
      resources: [@external_group],
      total_results: 1,
      start_index: 1

    url_root = if GitHub.enterprise?
      "https://github.com/api/v3"
    else
      "https://api.github.com"
    end

    expected_results = { "schemas" => ["urn:ietf:params:scim:api:messages:2.0:ListResponse"],
      "totalResults" => 1,
      "itemsPerPage" => 1,
      "startIndex" => 1,
      "Resources" => [
        {
          "schemas" => ["urn:ietf:params:scim:schemas:core:2.0:Group"],
          "id" => @external_group.guid,
          "externalId" => @external_group.external_id,
          "displayName" => @external_group.display_name,
          "meta" => {
            "resourceType" => "Group",
            "created" => @external_group.created_at,
            "lastModified" => @external_group.updated_at,
            "location" => "#{url_root}/scim/v2#{enterprise_slug}/Groups/#{@external_group.guid}",
          }
        }
      ]
    }

    result = enterprise_scim_groups(paginated_groups,
      { excluded_attributes: "members" })
    assert_equal expected_results, result
  end
end

class ScimSerializerGHESTest < Api::SerializerTestCase
  include AuthenticationHelpers::SAML
  include ScimSerializerSharedTests
  include ScimSerializerGroupSharedTests

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @serializer = Api::Serializer

    setup_saml_auth_mode(with_scim: true)
    @enterprise = create(:global_business)
    @provider = @enterprise.external_provider
    @provider.update(scim_provisioning_state: "scim_provisioning_state_enabled")

    @identity = create_identity
    @expected_attributes = create_expected_attributes(@identity)

    @external_group = create_external_group
    @external_identities = create_identities
  end

  setup do
    setup_saml_auth_mode(with_scim: true)
  end
end if GitHub.single_business_environment?

class ScimSerializerTest < Api::SerializerTestCase
  include ScimSerializerShared

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @enterprise = create(:business_saml_provider).business
    @organization = create(:organization)
    @enterprise.add_organization(@organization)
    @user = @organization.admin
    @serializer = Api::Serializer
  end

  context "#enterprise_scim_identity_hash" do
    test "returns nil unless passed an identity" do
      assert_nil enterprise_scim_identity
    end

    test "returns a hash of attributes related to the identity" do
      org_name = "FakeOrg"
      identity = create(:external_identity, provider: @enterprise.saml_provider, user: @user, scim_user_data:
        Platform::Provisioning::ScimUserData.new(
          [
            { "name" => "userName", "value" => Sham.email },
            { "name" => "externalId", "value" => Sham.sha },
            { "name" => "displayName", "value" => "#{Faker::Name.first_name} #{Faker::Name.last_name}" },
            { "name" => "name.givenName", "value" => Faker::Name.first_name },
            { "name" => "name.familyName", "value" => Faker::Name.last_name },
            { "name" => "name.formatted", "value" => "#{Faker::Name.first_name} #{Faker::Name.last_name}" },
            { "name" => "emails", "value" => Sham.email },
            { "name" => "groups", "value" => org_name },
            { "name" => "roles", "value" => "Owner" },
            { "name" => "active", "value" => "true" }
          ],
        )
      )

      expected_attributes = create_expected_attributes(identity, group_name: "FakeOrg")

      assert_equal expected_attributes, enterprise_scim_identity(identity)
      assert @serializer.serialize(:enterprise_scim_identity_hash, identity)["active"]
    end

    test "returns a false value for the active attribute when set" do
      identity = create(:external_identity, provider: @enterprise.saml_provider, user: @user, scim_user_data:
        Platform::Provisioning::ScimUserData.new(
          [
            { "name" => "userName", "value" => Sham.email },
            { "name" => "externalId", "value" => Sham.sha },
            { "name" => "active", "value" => "false" },
          ]
        )
      )

      refute_predicate identity.scim_user_data, :active?
      assert_equal false, enterprise_scim_identity(identity)["active"]
    end
  end

  context "#enterprise_group_hash" do
    test "returns nil unless passed an identity" do
      assert_nil enterprise_group
    end

    test "returns a hash of attributes for the group's identity, including SCIM-provisioned members" do
      scim_group_data = Platform::Provisioning::SCIMGroupData.new \
        [
           { "name" => "externalId", "value" => Sham.sha },
           { "name" => "displayName", "value" => @organization.login },
           { "name" => "userName", "value" => @organization.login },
        ]
      group_identity = create(:external_identity,
                              :group,
                              user: @organization,
                              provider: @enterprise.saml_provider,
                              scim_user_data: scim_group_data)
      member_user = create(:user)
      scim_user_data = Platform::Provisioning::ScimUserData.new \
        [
          { "name" => "userName", "value" => member_user.email },
          { "name" => "groups", "value" => @organization.login },
      ]
      member_identity = create(:external_identity,
                               :scim,
                               user: member_user,
                               provider: @enterprise.saml_provider,
                               scim_user_data: scim_user_data)
      @organization.add_member member_user

      admin_user_data = Platform::Provisioning::SamlUserData.new \
        [
          { "name" => "NameID", "value" => @user.email },
          { "name" => "groups", "value" => @organization.login },
      ]
      create(:external_identity, user: @user, provider: @enterprise.saml_provider,
             saml_user_data: admin_user_data)

      invited_user_data = Platform::Provisioning::ScimUserData.new \
        [
          { "name" => "userName", "value" => "invited-user@github.com" },
          { "name" => "groups", "value" => @organization.login },
      ]
      invited_identity = create :external_identity,
                                :unlinked,
                                provider: @enterprise.saml_provider,
                                organization_invitation: create(:organization_invitation, :email, organization: @organization),
                                scim_user_data: invited_user_data

      attributes_hash = enterprise_group(group_identity)
      assert_equal ["urn:ietf:params:scim:schemas:core:2.0:Group"], attributes_hash["schemas"]
      assert_equal group_identity.guid, attributes_hash["id"]
      assert_equal group_identity.scim_user_data.external_id, attributes_hash["externalId"]
      assert_equal group_identity.scim_user_data.display_name, attributes_hash["displayName"]
      url_root = if GitHub.enterprise?
        "https://github.com/api/v3"
      else
        "https://api.github.com"
      end
      expected_members = [
        {
          "value" => member_identity.guid,
          "$ref" => "#{url_root}/scim/v2/enterprises/#{@enterprise.slug}/Users/#{member_identity.guid}",
          "display" => member_identity.scim_user_data.display_name,
        },
        {
          "value" => invited_identity.guid,
          "$ref" => "#{url_root}/scim/v2/enterprises/#{@enterprise.slug}/Users/#{invited_identity.guid}",
          "display" => invited_identity.scim_user_data.display_name,
        }
      ]
      assert_same_elements expected_members, attributes_hash["members"],
                           "does not include any SAML-provisioned identities"
    end
  end

  context "#enterprise_groups_hash" do
    test "returns empty result set if given empty array" do
      paginated_identities = SCIM::ResultsCollection.new \
                               resources: ExternalIdentity.none,
                               total_results: 0,
                               start_index: 1

      expected_results = { "schemas" => ["urn:ietf:params:scim:api:messages:2.0:ListResponse"],
        "totalResults" => 0,
        "itemsPerPage" => 0,
        "startIndex" => 1,
        "Resources" => [],
      }
      assert_equal expected_results, enterprise_groups(paginated_identities)
    end
  end
end unless GitHub.single_business_environment?

class EmuScimSerializerTest < Api::SerializerTestCase
  include ScimSerializerSharedTests
  include ScimSerializerGroupSharedTests

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @serializer = Api::Serializer

    @enterprise = create(:business, :enterprise_managed)
    @owner = @enterprise.owners.first
    @provider = create(:business_saml_provider, business: @enterprise)
    @provider.update(scim_provisioning_state: "scim_provisioning_state_enabled")

    @identity = create_identity
    @expected_attributes = create_expected_attributes(@identity)

    @external_group = create_external_group
    @external_identities = create_identities
  end
end unless GitHub.single_business_environment?
