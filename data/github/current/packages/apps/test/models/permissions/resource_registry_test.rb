# typed: true
# frozen_string_literal: true

require "test_helper"

class ResourceRegistryTestResource < Permissions::FineGrainedResource
  ABILITY_TYPE_PREFIX = "ResourceRegistryTestResource"
  INDIVIDUAL_ABILITY_TYPE_PREFIX = ABILITY_TYPE_PREFIX
  ALL_ABILITY_TYPE_PREFIX = "Test/resource_registry_test_resource"
  SUBJECT_TYPES = %w(foo bar)
  READONLY_SUBJECT_TYPES = %w(foo)
  ADMINABLE_SUBJECT_TYPES = %w(bar)
  PREVIEW_SUBJECTS_AND_FEATURE_FLAGS = {
    test: :permissions_resource_registry
  }
end

class AnotherResourceRegistryTestResource < Permissions::FineGrainedResource
  ABILITY_TYPE_PREFIX = "AnotherResourceRegistryTestResource"
  INDIVIDUAL_ABILITY_TYPE_PREFIX = ABILITY_TYPE_PREFIX
  ALL_ABILITY_TYPE_PREFIX = "AnotherTest/another_resource_registry_test_resource"
  SUBJECT_TYPES = %w(baz quux ni)
  READONLY_SUBJECT_TYPES = %w(baz)
  WRITEONLY_SUBJECT_TYPES = %w(ni)
  ADMINABLE_SUBJECT_TYPES = %w(quux)
end

class PermissionsResourceRegistryTest < GitHub::TestCase
  def setup
    # ensure the singleton state is reset before each test
    singleton = Permissions::ResourceRegistry.instance
    singleton.instance_variable_names.each do |ivar|
      singleton.instance_variable_set(ivar, nil)
    end
  end

  context ".parent_of" do
    test "returns the parent type to which the given resource belongs" do
      repo = Repository.new

      assert_equal "Repository", Permissions::ResourceRegistry.parent_of(repo.resources.metadata.name)
    end
  end

  context ".all_prefixed_subject_types" do
    test "returns the subject types from all recorded fine grained resources" do
      Permissions::ResourceRegistry.any_instance.stubs(:all).returns([ResourceRegistryTestResource, AnotherResourceRegistryTestResource])

      expected_subject_types = ResourceRegistryTestResource.all_prefixed_subject_types + AnotherResourceRegistryTestResource.all_prefixed_subject_types

      expected_subject_types.each do |subject_type|
        assert_includes Permissions::ResourceRegistry.all_prefixed_subject_types, subject_type
      end
    end
  end

  context ".all_type_prefixed_subject_types" do
    test "returns the subject types from all recorded fine grained resources" do
      Permissions::ResourceRegistry.any_instance.stubs(:all).returns([ResourceRegistryTestResource, AnotherResourceRegistryTestResource])

      expected_subject_types = ResourceRegistryTestResource.all_type_prefixed_subject_types + AnotherResourceRegistryTestResource.all_type_prefixed_subject_types

      expected_subject_types.each do |subject_type|
        assert_includes Permissions::ResourceRegistry.all_type_prefixed_subject_types, subject_type
      end
    end
  end

  context ".individual_type_prefixed_subject_types" do
    test "returns the subject types from all recorded fine grained resources" do
      Permissions::ResourceRegistry.any_instance.stubs(:all).returns([ResourceRegistryTestResource, AnotherResourceRegistryTestResource])

      expected_subject_types = ResourceRegistryTestResource.individual_type_prefixed_subject_types + AnotherResourceRegistryTestResource.individual_type_prefixed_subject_types

      expected_subject_types.each do |subject_type|
        assert_includes Permissions::ResourceRegistry.individual_type_prefixed_subject_types, subject_type
      end
    end
  end

  context "preview subject types" do
    test "can be retrieved from the registry" do
      Permissions::ResourceRegistry.any_instance.stubs(:all).returns([ResourceRegistryTestResource])

      assert_equal :permissions_resource_registry, Permissions::ResourceRegistry.preview_subject_type_flags[:test]
      assert_includes Permissions::ResourceRegistry.all_preview_subject_types, :test
      assert Permissions::ResourceRegistry.preview_subject_type?(:test)
    end

    test "subject_type_enabled_for? checks feature enabled in flipper for actor" do
      Permissions::ResourceRegistry.any_instance.stubs(:all).returns([ResourceRegistryTestResource])
      actor = create(:user)
      integration = create(:integration)

      disable_feature_flag(:permissions_resource_registry)
      refute Permissions::ResourceRegistry.subject_type_enabled_for?(subject_type: :test, actor: actor, integration: integration)
      refute Permissions::ResourceRegistry.subject_type_enabled_for?(subject_type: :test, actor: actor)

      enable_feature_flag(:permissions_resource_registry, actor)
      assert Permissions::ResourceRegistry.subject_type_enabled_for?(subject_type: :test, actor: actor, integration: integration)
      assert Permissions::ResourceRegistry.subject_type_enabled_for?(subject_type: :test, actor: actor)

      enable_feature_flag(:permissions_resource_registry)
      actor_two = create(:organization, login: "actor-two")
      assert Permissions::ResourceRegistry.subject_type_enabled_for?(subject_type: :test, actor: actor_two, integration: integration)
      assert Permissions::ResourceRegistry.subject_type_enabled_for?(subject_type: :test, actor: actor_two)
    end

    test "subject_type_enabled_for? checks feature enabled in flipper for the owning org business" do
      Permissions::ResourceRegistry.any_instance.stubs(:all).returns([ResourceRegistryTestResource])
      actor = create(:user)
      organization = create(:organization, :enterprise_linked)
      integration = create(:integration, owner: organization)

      disable_feature_flag(:permissions_resource_registry)
      refute Permissions::ResourceRegistry.subject_type_enabled_for?(subject_type: :test, actor: actor, integration: integration)
      refute Permissions::ResourceRegistry.subject_type_enabled_for?(subject_type: :test, actor: actor)

      enable_feature_flag(:permissions_resource_registry, organization.business)
      assert Permissions::ResourceRegistry.subject_type_enabled_for?(subject_type: :test, actor: actor, integration: integration)

      enable_feature_flag(:permissions_resource_registry)
      actor_two = create(:organization, login: "actor-two")
      assert Permissions::ResourceRegistry.subject_type_enabled_for?(subject_type: :test, actor: actor_two, integration: integration)
      assert Permissions::ResourceRegistry.subject_type_enabled_for?(subject_type: :test, actor: actor_two)
    end

    test "subject_type_enabled_for? returns true for subject types that are not previews" do
      assert Permissions::ResourceRegistry.subject_type_enabled_for?(
        subject_type: "metadata",
        actor: :irrelevant,
      )
    end

    test "subject_type_enabled_for? checks if feature flag is enabled for integration" do
      Permissions::ResourceRegistry.any_instance.stubs(:all).returns([ResourceRegistryTestResource])
      actor = create(:user)
      integration = create(:integration)

      disable_feature_flag(:permissions_resource_registry)
      refute Permissions::ResourceRegistry.subject_type_enabled_for?(subject_type: :test, actor: actor, integration: integration)
      refute Permissions::ResourceRegistry.subject_type_enabled_for?(subject_type: :test, integration: integration)

      enable_feature_flag(:permissions_resource_registry, integration)
      assert Permissions::ResourceRegistry.subject_type_enabled_for?(subject_type: :test, actor: actor, integration: integration)
      assert Permissions::ResourceRegistry.subject_type_enabled_for?(subject_type: :test, integration: integration)

      enable_feature_flag(:permissions_resource_registry)
      actor_two = create(:organization, login: "actor-two")
      integration_two = create(:integration)
      assert Permissions::ResourceRegistry.subject_type_enabled_for?(subject_type: :test, actor: actor_two, integration: integration)
      assert Permissions::ResourceRegistry.subject_type_enabled_for?(subject_type: :test, integration: integration_two)
    end

    test ".readonly_subject_type?" do
      Permissions::ResourceRegistry.any_instance.stubs(:all).returns([ResourceRegistryTestResource, AnotherResourceRegistryTestResource])

      expected_subject_types = %w(foo baz)

      expected_subject_types.each do |subject_type|
        assert Permissions::ResourceRegistry.readonly_subject_type?(subject_type), "expected #{subject_type} to be a readonly resource"
      end
    end

    test ".writeonly_subject_type?" do
      Permissions::ResourceRegistry.any_instance.stubs(:all).returns([ResourceRegistryTestResource, AnotherResourceRegistryTestResource])

      expected_subject_types = %w(ni)

      expected_subject_types.each do |subject_type|
        assert Permissions::ResourceRegistry.writeonly_subject_type?(subject_type), "expected #{subject_type} to be a writeonly resource"
      end
    end

    test ".adminable_subject_type?" do
      Permissions::ResourceRegistry.any_instance.stubs(:all).returns([ResourceRegistryTestResource, AnotherResourceRegistryTestResource])

      expected_subject_types = %w(bar quux)

      expected_subject_types.each do |subject_type|
        assert Permissions::ResourceRegistry.adminable_subject_type?(subject_type), "expected #{subject_type} to be an adminable resource"
      end
    end
  end
end
