# typed: true
# frozen_string_literal: true

require "test_helper"

class Repositories::Domain::CustomPropertiesTest < GitHub::TestCase
  setup do
    @business = create :business
    @org = create :organization, name: "main-org", business: @business
    @repo = create :repository, owner: @org, name: "main-repo"
    @org_admin = @org.admins.first

    @definition_env = create :custom_property_definition, source: @org, property_name: "environment"
    @definition_security = create :custom_property_definition, source: @org, property_name: "security"
    @biz_definition_version = create :custom_property_definition, source: @business, property_name: "biz_version", required: true, default_value: "0.0.1"
  end

  sig { returns(Repositories::Domain::CustomProperties) }
  def domain
    Repositories.domain.custom_properties
  end

  context "values_for_repos" do
    test "returns correct values for repos, including from multiple orgs" do
      org2 = create :organization, name: "org-2"
      org2_repo1 = create :repository, owner: org2, name: "org2-repo1"
      org2_repo2 = create :repository, owner: org2, name: "org2-repo2"

      color_def = create(
        :custom_property_definition,
        source: org2,
        property_name: "color",
        default_value: "blue",
        required: true
      )
      color_val = create :custom_property_value, definition: color_def, target: org2_repo1, value: "red"

      definition_platform = create :custom_property_definition, :multi_select, source: org2
      ios_val = create :custom_property_value, definition: definition_platform, target: org2_repo1, value: "ios"
      web_val = create :custom_property_value, definition: definition_platform, target: org2_repo1, value: "web"

      org3 = create :organization, name: "org3"
      org3_repo1 = create :repository, owner: org3, name: "org3-repo1"

      expected = {
        @repo => [
          ValueWithDefinition.new(@biz_definition_version, []),
          ValueWithDefinition.new(@definition_env, []),
          ValueWithDefinition.new(@definition_security, []),
        ],
        org2_repo1 => [
          ValueWithDefinition.new(color_def, [color_val]),
          ValueWithDefinition.new(definition_platform, [ios_val, web_val]),
        ],
        org2_repo2 => [
          ValueWithDefinition.new(color_def, []),
          ValueWithDefinition.new(definition_platform, []),
        ],
        org3_repo1 => [],
      }

      assert_query_count_per_table({ custom_property_definitions: 2, custom_property_values: 1 }) do
        actual = domain.values_for_repos([@repo, org2_repo1, org2_repo2, org3_repo1])

        # property name sorting is also checked by this assert_equal because of how hash equality works
        assert_equal expected, actual
      end
    end

    test "enterprise definitions and values take precedence over org" do
      # Biz-level definition with duplicate name case-insensitive
      biz_definition_security = create :custom_property_definition, source: @business, property_name: "SECURITY"
      biz_security_value = create :custom_property_value, definition: biz_definition_security, target: @repo, value: "high"
      # Value should not be included as biz-level definition takes precedence
      create :custom_property_value, definition: @definition_security, target: @repo, value: "low"

      expected = {
        @repo => [
          ValueWithDefinition.new(@biz_definition_version, []),
          ValueWithDefinition.new(@definition_env, []),
          # Business `SECURITY` wins over org level `security`
          ValueWithDefinition.new(biz_definition_security, [biz_security_value]),
        ],
      }

      assert_query_count_per_table({ custom_property_definitions: 2, custom_property_values: 1 }) do
        actual = domain.values_for_repos([@repo])
        assert_equal expected, actual
      end
    end

    unless GitHub.enterprise?
      test "runs only one query to select definitions if org has no business", skip_with_all_emus: true do
        org = create :organization
        repo = create :repository, owner: org

        expected = {
          repo => [],
        }

        assert_query_count_per_table({ custom_property_definitions: 1, custom_property_values: 1 }) do
          actual = domain.values_for_repos([repo])
          assert_equal expected, actual
        end
      end

      test "returns correct values for repos, including from multiple enterprises" do
        biz_version_val = create :custom_property_value, definition: @biz_definition_version, target: @repo, value: "1.0"

        org2 = create :enterprise_linked_organization, name: "org-2"
        org2_repo = create :repository, owner: org2, name: "org2-repo1"

        color_def = create(:custom_property_definition, source: org2, property_name: "color", default_value: "blue", required: true)
        create :custom_property_value, definition: color_def, target: org2_repo, value: "red"

        biz_color_def = create(:custom_property_definition, source: org2.business, property_name: "color", default_value: "blue", required: true)
        biz_color_val = create :custom_property_value, definition: biz_color_def, target: org2_repo, value: "green"

        org3 = create :enterprise_linked_organization, name: "org3"
        org3_repo = create :repository, owner: org3, name: "org3-repo1"

        expected = {
          @repo => [
            ValueWithDefinition.new(@biz_definition_version, [biz_version_val]),
            ValueWithDefinition.new(@definition_env, []),
            ValueWithDefinition.new(@definition_security, []),
          ],
          org2_repo => [
            ValueWithDefinition.new(biz_color_def, [biz_color_val]),
          ],
          org3_repo => [],
        }

        assert_query_count_per_table({ custom_property_definitions: 2, custom_property_values: 1 }) do
          actual = domain.values_for_repos([@repo, org2_repo, org3_repo])

          # property name sorting is also checked by this assert_equal because of how hash equality works
          assert_equal expected, actual
        end
      end
    end

    test "does not rely on organization_id to check that repo repo owner is org", skip_with_all_emus: true do
      collaborator = create :user
      private_repo = create :private_repository, owner: @org
      private_repo.add_member(collaborator, action: :admin)


      @business.allow_private_repository_forking(actor: @business.owners.first, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)
      @org.allow_private_repository_forking(actor: collaborator)

      forked_repo = create(:fork_repository, forker: collaborator, fork_repo: private_repo)

      assert_equal forked_repo.organization_id, @org.id
      assert_equal forked_repo.owner, collaborator

      exception = assert_raises ArgumentError do
        domain.values_for_repos([forked_repo])
      end
      assert_equal exception.message, "all repos must belong to an organization"
    end

    test "throws error when any repos not in an org", skip_with_all_emus: true do
      assert_raises ArgumentError do
        domain.values_for_repos([@repo, create(:repository, owner: create(:user))])
      end
    end
  end

  context "values_hash_to_string_hash" do
    test "returns correct values" do
      # @definition_security has no default, needs no value

      # @definition_env has no default
      value_env = create :custom_property_value, definition: @definition_env, target: @repo, value: "prod"

      definition_with_default = create(
        :custom_property_definition,
        source: @org,
        property_name: "bird",
        default_value: "raven",
        required: true
      )

      definition_with_default_2 = create(
        :custom_property_definition,
        source: @org,
        property_name: "color",
        default_value: "blue",
        required: true
      )
      value_for_default_2 = create :custom_property_value, definition: definition_with_default_2, target: @repo, value: "red"

      definition_multiselect = create(
        :custom_property_definition,
        source: @org,
        property_name: "team",
        value_type: "multi_select",
        allowed_values: %w[eng sales],
      )

      multiselect_value_1 = create :custom_property_value, definition: definition_multiselect, target: @repo, value: "eng"
      multiselect_value_2 = create :custom_property_value, definition: definition_multiselect, target: @repo, value: "sales"

      definition_multiselect_without_values = create(
        :custom_property_definition,
        source: @org,
        property_name: "squad",
        value_type: "multi_select",
        allowed_values: %w[eng sales],
      )

      value_hash = {
        @repo => [
          ValueWithDefinition.new(@definition_security, []), # no default, no value
          ValueWithDefinition.new(@definition_env, [value_env]), # no default, has value
          ValueWithDefinition.new(definition_with_default, []), # has default, no value
          ValueWithDefinition.new(definition_with_default_2, [value_for_default_2]), # has default, has value
          ValueWithDefinition.new(definition_multiselect, [multiselect_value_1, multiselect_value_2]), # multi-select value
          ValueWithDefinition.new(definition_multiselect_without_values, []), # multi-select w/o value
        ],
      }

      expected_manual_no_strip = {
        @repo => {
          "security" => nil,
          "environment" => "prod",
          "bird" => nil,
          "color" => "red",
          "team" => %w[eng sales],
          "squad" => nil,
        },
      }

      expected_manual_strip = {
        @repo => {
          "environment" => "prod",
          "color" => "red",
          "team" => %w[eng sales],
        },
      }

      expected_effective_no_strip = {
        @repo => {
          "security" => nil,
          "environment" => "prod",
          "bird" => "raven",
          "color" => "red",
          "team" => %w[eng sales],
          "squad" => nil,
        },
      }

      expected_effective_strip = {
        @repo => {
          "environment" => "prod",
          "bird" => "raven",
          "color" => "red",
          "team" => %w[eng sales],
        },
      }

      assert_equal expected_manual_no_strip, domain.values_hash_to_string_hash(value_hash, :manual)
      assert_equal expected_manual_strip, domain.values_hash_to_string_hash(value_hash, :manual, strip_nils: true)
      assert_equal expected_effective_no_strip, domain.values_hash_to_string_hash(value_hash, :effective)
      assert_equal expected_effective_strip, domain.values_hash_to_string_hash(value_hash, :effective, strip_nils: true)
    end
  end

  context "#repo_properties" do
    test "returns correct values" do
      # @definition_security has no default, needs no value

      # @definition_env has no default
      create :custom_property_value, definition: @definition_env, target: @repo, value: "prod"

      definition_with_default = create(
        :custom_property_definition,
        source: @org,
        property_name: "bird",
        default_value: "raven",
        required: true
      )

      definition_with_default_2 = create(
        :custom_property_definition,
        source: @org,
        property_name: "color",
        default_value: "blue",
        required: true
      )
      create :custom_property_value, definition: definition_with_default_2, target: @repo, value: "red"

      expected_manual_no_strip = {
        @repo => {
          "security" => nil,
          "environment" => "prod",
          "bird" => nil,
          "color" => "red",
          "biz_version" => nil,
        },
      }

      expected_manual_strip = {
        @repo => {
          "environment" => "prod",
          "color" => "red",
        },
      }

      expected_effective_no_strip = {
        @repo => {
          "security" => nil,
          "environment" => "prod",
          "bird" => "raven",
          "color" => "red",
          "biz_version" => "0.0.1",
        },
      }

      expected_effective_strip = {
        @repo => {
          "environment" => "prod",
          "bird" => "raven",
          "color" => "red",
          "biz_version" => "0.0.1",
        },
      }

      assert_equal expected_manual_no_strip, domain.repo_properties([@repo], :manual)
      assert_equal expected_manual_strip, domain.repo_properties([@repo], :manual, strip_nils: true)
      assert_equal expected_effective_no_strip, domain.repo_properties([@repo], :effective)
      assert_equal expected_effective_strip, domain.repo_properties([@repo], :effective, strip_nils: true)
    end

    test "enterprise default value wins over org default value if properties with the same name exist" do
      create :custom_property_definition, source: @business, property_name: "cost_center", required: true, default_value: "US"
      create :custom_property_definition, source: @org, property_name: "COST_center", required: true, default_value: "EU"

      repo = create :repository, owner: @org
      expected = {
        repo => {
          "biz_version" => "0.0.1",
          "cost_center" => "US",
        }
      }

      assert_equal expected, domain.repo_properties([repo], :effective, strip_nils: true)
    end

    test "repo value is ignored if it is set for org definition and duplicate enterprise definition exists" do
      repo = create :repository, owner: @org

      create :custom_property_definition, source: @business, property_name: "cost_center", required: true, default_value: "US"
      org_def_cost_center = create :custom_property_definition, source: @org, property_name: "COST_center", required: true, default_value: "EU"
      create :custom_property_value, definition: org_def_cost_center, target: repo, value: "Asia"

      expected = {
        repo => {
          "biz_version" => "0.0.1",
          "cost_center" => "US",
        }
      }

      assert_equal expected, domain.repo_properties([repo], :effective, strip_nils: true)
    end

    test "correct values are picked if duplicate definitions for org and enterprise exist" do
      repo = create :repository, owner: @org

      biz_def_cost_center = create :custom_property_definition, source: @business, property_name: "cost_center", required: true, default_value: "US"
      create :custom_property_value, definition: biz_def_cost_center, target: repo, value: "Africa"
      org_def_cost_center = create :custom_property_definition, source: @org, property_name: "COST_center", required: true, default_value: "Africa"
      create :custom_property_value, definition: org_def_cost_center, target: repo, value: "Asia"

      expected = {
        repo => {
          "biz_version" => "0.0.1",
          "cost_center" => "Africa",
        }
      }

      assert_equal expected, domain.repo_properties([repo], :effective, strip_nils: true)
    end
  end

  context "can_see_property_definitions?" do
    test "org admin can see property definitions" do
      assert domain.can_see_property_definitions?(@org_admin, @org)
    end

    test "user member can see property definitions" do
      member = create :user
      @org.add_member(member)

      assert domain.can_see_property_definitions?(member, @org)
    end

    test "user cannot see property definitions" do
      user = create :user

      refute domain.can_see_property_definitions?(user, @org)
    end

    test "app can see property definitions" do
      integration = create :integration, default_permissions: { "organization_custom_properties" => :read, "metadata" => :read }, owner: @org_admin
      installation = make_integration_installation integration: integration, target: @org

      assert domain.can_see_property_definitions?(installation, @org)
    end

    test "app cannot see property definitions" do
      integration = create :integration, default_permissions: { "metadata" => :read }, owner: @org_admin
      installation = make_integration_installation integration: integration, target: @org

      refute domain.can_see_property_definitions?(installation, @org)
    end
  end
end
