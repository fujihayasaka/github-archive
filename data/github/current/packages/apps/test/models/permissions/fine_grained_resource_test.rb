# typed: true
# frozen_string_literal: true

require "test_helper"

class ATestFineGrainedResource < Permissions::FineGrainedResource
  SUBJECT_TYPES = %w(foo bar baz)
  ABILITY_TYPE_PREFIX = "ATestFineGrainedResource"
end

class ADifferentFineGrainedResource < Permissions::FineGrainedResource
  SUBJECT_TYPES = %w(chunky bacon)
  ALL_ABILITY_TYPE_PREFIX = "All"
  INDIVIDUAL_ABILITY_TYPE_PREFIX = "Individual"
  ABILITY_TYPE_PREFIX = INDIVIDUAL_ABILITY_TYPE_PREFIX
end

class AThirdFineGrainedResource < Permissions::FineGrainedResource
  PUBLIC_SUBJECT_TYPES = %w(never gonna give)

  PREVIEW_SUBJECTS_AND_FEATURE_FLAGS = {
    "you"   => :up,
    "n3v3r" => :gonna,
    "let"   => :you,
    "run"   => :run,
    "rick"  => :roll,
  }

  PREVIEW_SUBJECT_TYPES = PREVIEW_SUBJECTS_AND_FEATURE_FLAGS.keys
  ENTERPRISE_SUBJECT_TYPES = %w(down n3ver).freeze
  CONNECT_ONLY_SUBJECT_TYPES = %w(g0nna l3t).freeze

  SUBJECT_TYPES = if GitHub.enterprise?
    PUBLIC_SUBJECT_TYPES + PREVIEW_SUBJECT_TYPES + ENTERPRISE_SUBJECT_TYPES
  else
    PUBLIC_SUBJECT_TYPES + PREVIEW_SUBJECT_TYPES
  end

  EXCLUDED_SUBJECT_TYPES_FOR_TYPE = {
    Integration => %w(give you n3ver l3t),
  }.freeze

  ABILITY_TYPE_PREFIX = "AThirdFineGrainedResource"
end

class PermissionsFineGrainedResourceTest < GitHub::TestCase
  fixtures do
    @integration = create(:integration)
  end

  def verify_resource_inclusion(actor, resource)
    if AThirdFineGrainedResource::EXCLUDED_SUBJECT_TYPES_FOR_TYPE[actor.class].include?(resource)
      refute_includes AThirdFineGrainedResource.subject_types_for(actor), resource
    else
      assert_includes AThirdFineGrainedResource.subject_types_for(actor), resource
    end
  end

  context "subclassing" do
    test "defines a method for each subject type of the resource" do
      fgp = ATestFineGrainedResource.new(:parent)

      assert fgp.respond_to?(:foo)
      assert fgp.respond_to?(:bar)
      assert fgp.respond_to?(:baz)
    end

    test "defines a method that returns the parent resource" do
      fgp = ATestFineGrainedResource.new(:parent)

      assert fgp.respond_to?(:a_test_fine_grained_resource)
      assert_equal :parent, T.unsafe(fgp).a_test_fine_grained_resource
    end

    context "constructing valid ability collections" do
      test "returns the correct value for the sub-resource" do
        fgp = ATestFineGrainedResource.new(:parent)
        other_fgp = ADifferentFineGrainedResource.new(:other_parent)

        assert_equal "ATestFineGrainedResource/foo", T.unsafe(fgp).foo.ability_type
        assert_equal :parent, T.unsafe(fgp).foo.parent

        assert_equal "Individual/chunky", T.unsafe(other_fgp).chunky.ability_type
        assert_equal :other_parent, T.unsafe(other_fgp).chunky.parent
      end
    end

    test "defines a method that returns all subject types for the resource" do
      assert_equal %w(foo bar baz), ATestFineGrainedResource.subject_types
    end

    test "defines a method that returns all prefixed subject types defined in the resource" do
      expected_subject_types = %w(ATestFineGrainedResource/foo ATestFineGrainedResource/bar ATestFineGrainedResource/baz)

      assert_same_elements expected_subject_types, ATestFineGrainedResource.all_prefixed_subject_types
    end

    test "defines a method that returns all prefixed subject types for resources that define 'all' and 'individual' subject type prefixes" do
      expected_subject_types = %w(All/chunky All/bacon Individual/chunky Individual/bacon)

      assert_same_elements expected_subject_types, ADifferentFineGrainedResource.all_prefixed_subject_types
    end

    test "defines a method that returns prefixed subject types for resources that define 'all' subject type prefixes" do
      expected_subject_types = %w(All/chunky All/bacon)

      assert_same_elements expected_subject_types, ADifferentFineGrainedResource.all_type_prefixed_subject_types
    end

    test "filters the results of prefixed subject types for resources that defined 'all' subject type prefixes" do
      expected_subject_types = %w(All/chunky)

      assert_same_elements expected_subject_types, ADifferentFineGrainedResource.all_type_prefixed_subject_types(["chunky"])
    end

    test "defines a method that returns individual prefixed subject types for resources that define 'individual' subject type prefixes" do
      expected_subject_types = %w(Individual/chunky Individual/bacon)

      assert_same_elements expected_subject_types, ADifferentFineGrainedResource.individual_type_prefixed_subject_types
    end

    test "filters the results of individual prefixed subject types for resources that define 'individual' subject type prefixes" do
      expected_subject_types = %w(Individual/bacon)

      assert_same_elements expected_subject_types, ADifferentFineGrainedResource.individual_type_prefixed_subject_types(["bacon"])
    end

    context ".subject_types_for" do
      test "includes expected PUBLIC_SUBJECT_TYPES" do
        AThirdFineGrainedResource::PUBLIC_SUBJECT_TYPES.each do |resource|
          verify_resource_inclusion(@integration, resource)
        end
      end

      test "includes expected CONNECT_ONLY_SUBJECT_TYPES" do
        @integration.stub(:connect_app?, true) do
          AThirdFineGrainedResource::CONNECT_ONLY_SUBJECT_TYPES.each do |resource|
            verify_resource_inclusion(@integration, resource)
          end
        end
      end

      test "returns expected ENTERPRISE_SUBJECT_TYPES", enterprise_only: true do
        AThirdFineGrainedResource::ENTERPRISE_SUBJECT_TYPES.each do |resource|
          verify_resource_inclusion(@integration, resource)
        end
      end

      test "does not return any ENTERPRISE_SUBJECT_TYPES", skip_enterprise: true do
        AThirdFineGrainedResource::ENTERPRISE_SUBJECT_TYPES.each do |resource|
          refute_includes AThirdFineGrainedResource.subject_types_for(@integration), resource
        end
      end

      test "does not return any EXCLUDED_SUBJECT_TYPES_FOR_TYPE" do
        enable_feature_flag(:up, @integration) # Enabling an excluded permission

        AThirdFineGrainedResource::EXCLUDED_SUBJECT_TYPES_FOR_TYPE.each do |resource|
          refute_includes AThirdFineGrainedResource.subject_types_for(@integration), resource
        end
      end

      test "returns subject types from PREVIEW_SUBJECTS_AND_FEATURE_FLAGS if the integration has the feature flag enabled" do
        enable_feature_flag(:up, @integration)
        enable_feature_flag(:gonna, @integration)
        disable_feature_flag(:you, @integration)
        enable_feature_flag(:run, @integration.owner)

        business_org = create(:organization, :enterprise_linked)
        integration = create(:integration, owner: business_org)
        enable_feature_flag(:roll, business_org.business)

        assert_includes AThirdFineGrainedResource.subject_types_for(@integration), "n3v3r"
        assert_includes AThirdFineGrainedResource.subject_types_for(@integration), "run"
        refute_includes AThirdFineGrainedResource.subject_types_for(@integration), "you" # This is in the exclusion list for Integration actors
        refute_includes AThirdFineGrainedResource.subject_types_for(@integration), "let"
        assert_includes AThirdFineGrainedResource.subject_types_for(integration), "rick"
      end
    end

    context "#collection_for" do
      test "returns nil for an invalid resource name" do
        assert_nil ATestFineGrainedResource.new(:parent).collection_for("nothing")
      end

      test "returns ability collection with the same parent and name" do
        ability_collection = ATestFineGrainedResource.new(:parent).collection_for("foo")

        assert_instance_of IntegrationInstallation::AbilityCollection, ability_collection
        assert_equal :parent, ability_collection.parent
        assert_equal "foo", ability_collection.name
      end
    end

    test ".filter removes permissions that aren't part of the subject_types" do
      permissions = { "foo" => :read, "bar" => :write, "beep" => :write }
      assert_same_hash({ "foo" => :read, "bar" => :write },  ATestFineGrainedResource.filter(permissions))
    end
  end
end
