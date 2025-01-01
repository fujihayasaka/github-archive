# typed: true
# frozen_string_literal: true

require "test_helper"

class CustomProperties::PublicTest < GitHub::TestCase
  include PerformanceTestHelpers
  include CustomPropertiesTestHelper

  include CustomProperties
  include CustomProperties::Errors

  setup do
    @business = create :business
    @org = create :organization, name: "main-org", business: @business
    @repo = create :repository, owner: @org, name: "main-repo"

    @definition_env = create :custom_property_definition, source: @org, property_name: "environment"
    create :custom_property_usage, definition: @definition_env
    @definition_security = create :custom_property_definition, source: @org, property_name: "security"
    @biz_definition_version = create :custom_property_definition, source: @business, property_name: "biz_version", required: true, default_value: "0.0.1"
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
        actual = Public.values_for_repos([@repo, org2_repo1, org2_repo2, org3_repo1])

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
        actual = Public.values_for_repos([@repo])
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
          actual = Public.values_for_repos([repo])
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
          actual = Public.values_for_repos([@repo, org2_repo, org3_repo])

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
        Public.values_for_repos([forked_repo])
      end
      assert_equal exception.message, "all repos must belong to an organization"
    end

    test "throws error when any repos not in an org", skip_with_all_emus: true do
      assert_raises ArgumentError do
        Public.values_for_repos([@repo, create(:repository, owner: create(:user))])
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

      assert_equal expected_manual_no_strip, Public.values_hash_to_string_hash(value_hash, :manual)
      assert_equal expected_manual_strip, Public.values_hash_to_string_hash(value_hash, :manual, strip_nils: true)
      assert_equal expected_effective_no_strip, Public.values_hash_to_string_hash(value_hash, :effective)
      assert_equal expected_effective_strip, Public.values_hash_to_string_hash(value_hash, :effective, strip_nils: true)
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

      assert_equal expected_manual_no_strip, Public.repo_properties([@repo], :manual)
      assert_equal expected_manual_strip, Public.repo_properties([@repo], :manual, strip_nils: true)
      assert_equal expected_effective_no_strip, Public.repo_properties([@repo], :effective)
      assert_equal expected_effective_strip, Public.repo_properties([@repo], :effective, strip_nils: true)
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

      assert_equal expected, Public.repo_properties([repo], :effective, strip_nils: true)
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

      assert_equal expected, Public.repo_properties([repo], :effective, strip_nils: true)
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

      assert_equal expected, Public.repo_properties([repo], :effective, strip_nils: true)
    end
  end

  # the two authzd calls in this method are tested on their own, so this test is slim
  context "user_edit_permissions" do
    test "returns true for org admin and repo admin" do
      expected_count = 1
      assert_authzd_calls(single: 0, batch: expected_count) do
        permissions = Public.user_edit_permissions(@org.admins.first, @repo)
        assert permissions.org
        assert permissions.repo
      end

      user = create :user
      @repo.add_member(user, action: :admin)
      assert_authzd_calls(single: 0, batch: expected_count) do
        perms = Public.user_edit_permissions(user, @repo)
        refute perms.org
        assert perms.repo
      end
    end

    test "returns false for random user" do
      expected_count = 1
      assert_authzd_calls(single: 0, batch: expected_count) do
        perms = Public.user_edit_permissions(create(:user), @repo)
        refute perms.org
        refute perms.repo
      end
    end

    test "returns false if user-owned repo provided" do
      user = create :user
      user_repo = create :repository, owner: user
      assert_authzd_calls(single: 0, batch: 0) do
        perms = Public.user_edit_permissions(user, user_repo)
        refute perms.org
        refute perms.repo
      end
    end
  end

  context "destroy_all_definitions" do
    test "should delete all definitions of the given org and their usages" do
      events = subscribe "custom_property_definition.destroy"
      second_org = create :organization
      definition = create :custom_property_definition, source: second_org
      create :custom_property_usage, definition: definition
      create :custom_property_usage, definition: definition

      assert_equal CustomPropertyDefinition.defined_by(@org).count, 2
      assert_equal CustomPropertyDefinition.defined_by(@org).flat_map(&:usages).size, 1

      assert_equal CustomPropertyDefinition.defined_by(second_org).count, 1
      assert_equal CustomPropertyDefinition.defined_by(second_org).flat_map(&:usages).size, 2

      Public.destroy_all_definitions(second_org)

      assert_equal CustomPropertyDefinition.defined_by(@org).count, 2
      assert_equal CustomPropertyDefinition.defined_by(@org).flat_map(&:usages).size, 1

      assert_equal CustomPropertyDefinition.defined_by(second_org).count, 0
      assert_equal CustomPropertyDefinition.defined_by(second_org).flat_map(&:usages).size, 0

      refute_nil event = events.pop, "an event was expected"
      expected_payload = {
        definition_id: definition.id,
        property_name: definition.property_name,
        description: nil,
        value_type: "string",
        org: second_org.name,
        org_id: second_org.id,
        required: false,
        default_value: nil,
        allowed_values: nil,
      }
      assert_equal expected_payload, event.payload
    end

    test "keeps enterprise definitions when destroying for org" do
      assert_equal CustomPropertyDefinition.defined_by(@org).count, 2
      assert_equal CustomPropertyDefinition.defined_by(@business).count, 1

      Public.destroy_all_definitions(@org)

      assert_equal CustomPropertyDefinition.defined_by(@org).count, 0
      assert_equal CustomPropertyDefinition.defined_by(@business).count, 1
    end

    test "destroys enterprise definitions" do
      assert_equal CustomPropertyDefinition.defined_by(@org).count, 2
      assert_equal CustomPropertyDefinition.defined_by(@business).count, 1

      Public.destroy_all_definitions(@business)

      assert_equal CustomPropertyDefinition.defined_by(@org).count, 2
      assert_equal CustomPropertyDefinition.defined_by(@business).count, 0
    end
  end

  context "destroy_all_properties" do
    test "throws if invalid entity type" do
      exception = assert_raises TypeError do
        Public.destroy_all_properties(create(:user))
      end
      assert exception.message.start_with?("Parameter 'entity': Expected type Repository, got type User")
    end

    test "deletes all properties" do
      custom_property_events = subscribe("custom_property.destroy")
      custom_property_value_events = subscribe("custom_property_value.destroy")
      create :custom_property_value, target: @repo, definition: @definition_env, value: "value"

      assert_equal repo_properties(@repo, :manual), { "environment" => "value" }

      repo_to_keep = create :repository, owner: @org
      create :custom_property_value, target: repo_to_keep, definition: @definition_env, value: "value"

      Public.destroy_all_properties(@repo)
      assert_empty CustomPropertyValue.for_target(@repo)
      assert_equal repo_properties(repo_to_keep, :manual), { "environment" => "value" }

      refute_nil custom_property_value_event = custom_property_value_events.pop, "an event was expected"
      expected_custom_property_value_event = {
        definition_id: @definition_env.id,
        property_name: @definition_env.property_name,
        value: "value",
        repo: @repo.name_with_display_owner,
        repo_id: @repo.id,
        org: @org.display_login,
        org_id: @org.id,
        public_repo: TestEnv.test_with_all_emus? ? false : true,
      }

      assert_equal expected_custom_property_value_event, custom_property_value_event.payload
    end

    context "property_usage" do
      test "gets 0 if no usages" do
        definition = create :custom_property_definition, source: @org, property_name: "unused"

        usage = Public.property_usage(definition)
        assert_equal 0, usage[:repositories_count]
      end

      test "gets the number of repos using a property" do
        create :custom_property_value, definition: @definition_env, target: @repo, value: "prod"

        usage = Public.property_usage(@definition_env)
        assert_equal 1, usage[:repositories_count]
      end

      test "gets 0 if used on a deleted repo" do
        repo = create :repository, :soft_deleted, owner: @org
        create :custom_property_value, definition: @definition_env, target: repo, value: "prod"

        assert_query_count(1) do
          usage = Public.property_usage(@definition_env)
          assert_equal 0, usage[:repositories_count]
        end
      end

      test "returns correct count for business property" do
        create :custom_property_value, definition: @biz_definition_version, target: @repo, value: "1.0.0"

        usage = Public.property_usage(@biz_definition_version)
        assert_equal 1, usage[:repositories_count]
      end
    end

    context "shared definitions cache" do
      test "shares definitions cache between managers" do
        definitions_manager = Public.definitions_manager(@org)
        values_manager = Public.values_manager(definitions_manager)

        assert_query_count_per_table({ custom_property_definitions: 1 }) do
          definitions_manager.get_definitions
          values_manager.set_properties_for([@repo], { "environment" => "value" }, actor: @org.admin)
        end
      end

      test "invalidates cache" do
        definitions_manager = Public.definitions_manager(@org)
        values_manager = Public.values_manager(definitions_manager)

        assert_query_count_per_table({
          custom_property_definitions: 3 # 2 select + 1 insert
        }) do
          definitions_manager.save_definition(property_name: "version")
          values_manager.set_properties_for([@repo], { "version" => "1.0.0" }, actor: @org.admin)
        end
      end
    end

    test "does not check if owner is org" do
      user = create :user
      repo = create :repository, owner: user

      Public.destroy_all_properties(@repo)
      assert_empty CustomPropertyValue.for_target(@repo)
    end
  end
end
