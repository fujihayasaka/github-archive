# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class PermissionsEntryPointHydroDecoratorTest < GitHub::TestCase
  include PermissionsHelper

  fixtures do
    @target = create(:organization)
    @installation = make_integration_installation(target: @target)
    @integration = @installation.integration
  end

  def create_actor_context(actor: @installation, target: @target, owner: @integration, write_type: Permissions::EntryPoint::WriteType::CREATE)
    Permissions::EntryPoint::ActorContext.new(
      entry_point_tag: "test_case",
      total: 10,
      actor_id: actor&.id,
      actor_type: actor&.class&.name,
      target: target,
      owner: owner,
      write_type: write_type,
    )
  end

  context "#actor_type" do
    test "adds correct prefix and capitalization" do
      decorator = Permissions::EntryPoint::HydroDecorator.new(create_actor_context)
      assert_equal "ACTOR_TYPE_INTEGRATION_INSTALLATION", decorator.actor_type
    end

    test "returns default value for invalid actor types" do
      decorator = Permissions::EntryPoint::HydroDecorator.new(create_actor_context(actor: @integration))
      assert_equal :ACTOR_TYPE_UNKNOWN, decorator.actor_type
    end
  end

  context "#target_type" do
    test "adds correct prefix and capitalization" do
      decorator = Permissions::EntryPoint::HydroDecorator.new(create_actor_context)
      assert_equal "TARGET_TYPE_ORGANIZATION", decorator.target_type
    end

    test "returns default value for invalid target types" do
      decorator = Permissions::EntryPoint::HydroDecorator.new(create_actor_context(target: nil))
      assert_equal :TARGET_TYPE_UNKNOWN, decorator.target_type
    end
  end

  context "#owner_type" do
    test "adds correct prefix and capitalization" do
      decorator = Permissions::EntryPoint::HydroDecorator.new(create_actor_context)
      assert_equal "ACTOR_OWNER_TYPE_INTEGRATION", decorator.owner_type
    end

    test "returns default value for invalid owner types" do
      decorator = Permissions::EntryPoint::HydroDecorator.new(create_actor_context(owner: nil))
      assert_equal :ACTOR_OWNER_TYPE_UNKNOWN, decorator.owner_type
    end
  end

  context "#write_type" do
    test "returns :WRITE_TYPE_CREATE for WriteType::CREATE" do
      actor_context = create_actor_context(write_type: Permissions::EntryPoint::WriteType::CREATE)
      decorator = Permissions::EntryPoint::HydroDecorator.new(actor_context)
      assert_equal :WRITE_TYPE_CREATE, decorator.write_type
    end

    test "returns :WRITE_TYPE_UPDATE for WriteType::UPDATE" do
      actor_context = create_actor_context(write_type: Permissions::EntryPoint::WriteType::UPDATE)
      decorator = Permissions::EntryPoint::HydroDecorator.new(actor_context)
      assert_equal :WRITE_TYPE_UPDATE, decorator.write_type
    end

    test "returns :WRITE_TYPE_DELETE for WriteType::DELETE" do
      actor_context = create_actor_context(write_type: Permissions::EntryPoint::WriteType::DELETE)
      decorator = Permissions::EntryPoint::HydroDecorator.new(actor_context)
      assert_equal :WRITE_TYPE_DELETE, decorator.write_type
    end
  end
end
