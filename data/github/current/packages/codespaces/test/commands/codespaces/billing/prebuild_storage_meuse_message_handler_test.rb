# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::Billing::PrebuildStorageMeuseMessageHandlerTest < GitHub::TestCase
  include CodespacesPlanFixtures
  include DogstatsTestHelpers

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    GitHub.flipper[:codespaces_prebuild_billing_free].disable

    GitHub.flipper[:codespaces_billing_free].disable

    @owner = create(:credit_card_organization, plan: GitHub::Plan.business_plus)
    @repo = create(:private_repository, owner: @owner, from_example: :simple)

    @prebuild_template = create(:codespace_prebuild_template, repository: @repo)
    @billing_entry = @prebuild_template.billing_entry

    @billing_message = build(
      :codespace_ephemeral_billing_message,
      :without_compute,
      codespace_plan_id: @prebuild_template.plan.id,
      codespaces: [@prebuild_template]
    )
    @tracked_usage = @billing_message.tracked_usages_for(@billing_entry.prebuild_template_guid).find(&:is_storage?)
  end

  test "#transform_usage" do
    command = Codespaces::Billing::PrebuildStorageMeuseMessageHandler.new(
      billing_entry: @billing_entry,
      billing_message: @billing_message,
      tracked_usage: @tracked_usage,
    )

    meuse_hash = command.send(:transform_usage)

    refute_nil meuse_hash[:usage_uuid]
    assert_equal("prebuild_storage", meuse_hash[:product_sku_name])
    assert_equal(Time.at(@billing_message.period_end), meuse_hash[:usage_at])
    assert_equal(@tracked_usage.computed_usage_in_gb_month, meuse_hash[:quantity])
    assert_equal(@billing_entry.billable_owner_id, meuse_hash[:account_id])
    assert_equal(@billing_message.source_uri, meuse_hash[:source_uri])
    assert_equal(@billing_entry.repository_id, meuse_hash[:custom_fields]["repository.id"])

    # Prebuilds do not have actors
    assert_nil(meuse_hash[:actor_id])
  end

  context "#perform" do
    test "returns usage" do
      owner = create(:credit_card_organization, plan: GitHub::Plan.business_plus)
      repo = create(:private_repository, owner: owner)

      @prebuild_template = create(:codespace_prebuild_template, repository: repo)

      command = Codespaces::Billing::PrebuildStorageMeuseMessageHandler.new(
        billing_entry: @billing_entry,
        billing_message: @billing_message,
        tracked_usage: @tracked_usage,
      )

      data = {
        usage_uuid: GitHub::Billing::MeteredProduct.usage_uuid(command.send(:unique_billing_identifier)),
        product_name: "codespaces",
        product_sku_name: "prebuild_storage",
        usage_at: Time.at(@billing_message.period_end),
        quantity: @tracked_usage.computed_usage_in_gb_month,
        account_id: @billing_entry.billable_owner.id,
        source_uri: @billing_message.source_uri,
        custom_fields: {
          "repository.id" => @billing_entry.repository.id,
        }
      }

      result = command.call
      assert_equal(result.hydro_topic, "meuse.metered_usage")
      assert (data.to_a - result.hydro_payload.to_a).empty?

      assert_dogstats_increment 1, "codespaces.billing_usage.dispatched.count",
        tags: ["class:codespaces/billing/prebuild_storage_meuse_message_handler"]
    end

    test "returns usage if billable owner is a business" do

      owner = create(:enterprise_linked_organization)
      repo = create(:private_repository, owner: owner)
      prebuild_template = create(:codespace_prebuild_template, repository: repo)
      billing_entry = prebuild_template.billing_entry

      # Use the billable_owner method on the org/user to handle delegating to businesses or other special cases
      billable_owner = billing_entry.billable_owner.billable_owner

      billing_message = build(
        :codespace_ephemeral_billing_message,
        :without_compute,
        codespace_plan_id: prebuild_template.plan.id,
        codespaces: [prebuild_template]
      )
      tracked_usage = billing_message.tracked_usages_for(billing_entry.prebuild_template_guid).find(&:is_storage?)


      command = Codespaces::Billing::PrebuildStorageMeuseMessageHandler.new(
        billing_entry: billing_entry,
        billing_message: billing_message,
        tracked_usage: tracked_usage,
      )

      data = {
        usage_uuid: GitHub::Billing::MeteredProduct.usage_uuid(command.send(:unique_billing_identifier)),
        product_name: "codespaces",
        product_sku_name: "prebuild_storage",
        usage_at: billing_message.period_end,
        quantity: tracked_usage.computed_usage_in_gb_month,
        account_id: billing_entry.billable_owner.id,
        source_uri: billing_message.source_uri,
        custom_fields: {
          "repository.id" => billing_entry.repository.id,
        }
      }

      result = command.call
      assert_equal(result.hydro_topic, "meuse.metered_usage")
      assert (data.to_a - result.hydro_payload.to_a).empty?

      assert billable_owner.is_a?(::Business)
      assert_equal owner.business, billable_owner
    end

    test "return usage if billing message location is a billable region" do
      prebuild_template = create(:codespace_prebuild_template, repository: @repo, location: "WestUs2")
      billing_entry = prebuild_template.billing_entry

      billing_message = build(
        :codespace_ephemeral_billing_message,
        :without_compute,
        codespace_plan_id: prebuild_template.plan.id,
        codespaces: [prebuild_template]
      )

      tracked_usage = billing_message.tracked_usages_for(billing_entry.prebuild_template_guid).find(&:is_storage?)

      command = Codespaces::Billing::PrebuildStorageMeuseMessageHandler.new(
        billing_entry: billing_entry,
        billing_message: billing_message,
        tracked_usage: tracked_usage,
      )

      result = command.call
      assert_equal(result.hydro_topic, "meuse.metered_usage")
    end

    test "does not return usage if billable_owner is nil" do

      @owner.destroy!
      @billing_entry.reload

      command = Codespaces::Billing::PrebuildStorageMeuseMessageHandler.new(
        billing_entry: @billing_entry,
        billing_message: @billing_message,
        tracked_usage: @tracked_usage,
      )

      GlobalInstrumenter.expects(:instrument).with("meuse.metered_usage").never

      command.call
    end

    test "does not return usage if billable owner has free prebuild usage" do
      GitHub.flipper[:codespaces_prebuild_billing_free].enable(@owner)
      command = Codespaces::Billing::PrebuildStorageMeuseMessageHandler.new(
        billing_entry: @billing_entry,
        billing_message: @billing_message,
        tracked_usage: @tracked_usage,
      )

      refute command.call
    end

    test "does not return usage if @tracked_usage is compute" do
      tracked_usage = @billing_message.tracked_usages_for(@billing_entry.prebuild_template_guid).find(&:is_compute?)

      command = Codespaces::Billing::PrebuildStorageMeuseMessageHandler.new(
        billing_entry: @billing_entry,
        billing_message: @billing_message,
        tracked_usage: tracked_usage,
      )

      refute command.call
    end

    test "does not return usage unless vscs_target is production" do
      prebuild_template = create(:codespace_prebuild_template, :ppe, repository: @repo, configuration: create(:codespace_prebuild_configuration, repository: @repo, vscs_target: :ppe))

      billing_entry = prebuild_template.billing_entry

      billing_message = build(
        :codespace_ephemeral_billing_message,
        :without_compute,
        codespace_plan_id: prebuild_template.plan.id,
        codespaces: [prebuild_template],
        vscs_target: prebuild_template.vscs_target
      )
      tracked_usage = billing_message.tracked_usages_for(billing_entry.prebuild_template_guid).find(&:is_storage?)

      command = Codespaces::Billing::PrebuildStorageMeuseMessageHandler.new(
        billing_entry: billing_entry,
        billing_message: billing_message,
        tracked_usage: tracked_usage,
      )

      refute command.call
    end

    test "does not return usage if billable owner has free usage" do

      GitHub.flipper[:codespaces_billing_free].enable(@owner)
      command = Codespaces::Billing::PrebuildStorageMeuseMessageHandler.new(
        billing_entry: @billing_entry,
        billing_message: @billing_message,
        tracked_usage: @tracked_usage,
      )

      refute command.call
    end

    test "does not return usage if billable owner (enterprise) has free usage" do

      owner = create(:enterprise_linked_organization)
      GitHub.flipper[:codespaces_billing_free].enable(owner.billable_owner)
      repo = create(:private_repository, owner: owner)

      prebuild_template = create(:codespace_prebuild_template, repository: repo)

      billing_entry = prebuild_template.billing_entry

      billing_message = build(
        :codespace_ephemeral_billing_message,
        :without_compute,
        codespace_plan_id: prebuild_template.plan.id,
        codespaces: [prebuild_template],
      )
      tracked_usage = billing_message.tracked_usages_for(billing_entry.prebuild_template_guid).find(&:is_storage?)

      command = Codespaces::Billing::PrebuildStorageMeuseMessageHandler.new(
        billing_entry: billing_entry,
        billing_message: billing_message,
        tracked_usage: tracked_usage,
      )
      refute command.call
    end

    test "does not return usage if computed usage is 0" do

      billing_message = build(
        :codespace_ephemeral_billing_message,
        :without_compute,
        codespace_plan_id: @prebuild_template.plan.id,
        codespaces: [@prebuild_template],
        storage_use: 0,
        size: 0
      )
      tracked_usage = billing_message.tracked_usages_for(@billing_entry.prebuild_template_guid).find(&:is_storage?)

      command = Codespaces::Billing::PrebuildStorageMeuseMessageHandler.new(
        billing_entry: @billing_entry,
        billing_message: billing_message,
        tracked_usage: tracked_usage,
      )

      assert tracked_usage.computed_usage_in_gb_month.zero?
      return command.call
    end

    test "does not return if computed usage is negative" do

      billing_message = build(
        :codespace_ephemeral_billing_message,
        :without_compute,
        codespace_plan_id: @prebuild_template.plan.id,
        codespaces: [@prebuild_template],
        storage_use: 1,
        size_in_kb: -68719476736,
      )
      tracked_usage = billing_message.tracked_usages_for(@billing_entry.prebuild_template_guid).find(&:is_storage?)

      command = Codespaces::Billing::PrebuildStorageMeuseMessageHandler.new(
        billing_entry: @billing_entry,
        billing_message: billing_message,
        tracked_usage: tracked_usage,
      )

      assert tracked_usage.computed_usage_in_gb_month.negative?
      refute command.call
    end

    test "does not return usage if billing message location isn't a billable region" do
      location = "AustraliaEast"
      configuration = create(:codespace_prebuild_configuration, repository: @repo, with_locations: [location])
      prebuild_template = create(:codespace_prebuild_template, repository: @repo, location: location, configuration: configuration)
      billing_entry = prebuild_template.billing_entry

      billing_message = build(
        :codespace_ephemeral_billing_message,
        :without_compute,
        codespace_plan_id: prebuild_template.plan.id,
        codespaces: [prebuild_template]
      )

      tracked_usage = billing_message.tracked_usages_for(billing_entry.prebuild_template_guid).find(&:is_storage?)

      command = Codespaces::Billing::PrebuildStorageMeuseMessageHandler.new(
        billing_entry: billing_entry,
        billing_message: billing_message,
        tracked_usage: tracked_usage,
      )

      refute command.call
    end

    context "if should_test_non_prod?" do
      test "does not log dev/ppe message if feature flag is disabled" do
        GitHub.flipper[:codespaces_billing_test_non_prod].disable
        @billing_message.stubs(:vscs_target).returns(:development)
        Codespaces::Billing::PrebuildStorageMeuseMessageHandler.any_instance.expects(:test_non_prod_usage).never
        Codespaces::Billing::PrebuildStorageMeuseMessageHandler.any_instance.expects(:transform_usage).never
        Codespaces::Billing::PrebuildStorageMeuseMessageHandler.any_instance.expects(:publish_usage).never
        Codespaces::Billing::PrebuildStorageMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
      end

      test "does not log dev/ppe message if it should not be published" do
        GitHub.flipper[:codespaces_billing_test_non_prod].enable
        @billing_message.stubs(:vscs_target).returns(:development)
        @billing_entry.stubs(:billable_owner).returns(nil)
        Codespaces::Billing::PrebuildStorageMeuseMessageHandler.any_instance.expects(:test_non_prod_usage).never
        Codespaces::Billing::PrebuildStorageMeuseMessageHandler.any_instance.expects(:transform_usage).never
        Codespaces::Billing::PrebuildStorageMeuseMessageHandler.any_instance.expects(:publish_usage).never
        Codespaces::Billing::PrebuildStorageMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
      end

      test "logs for dev/ppe if should normally publish & feature flag is on" do
        GitHub.flipper[:codespaces_billing_test_non_prod].enable
        @billing_message.stubs(:vscs_target).returns(:development)
        Codespaces::Billing::PrebuildStorageMeuseMessageHandler.any_instance.expects(:test_non_prod_usage)
        Codespaces::Billing::PrebuildStorageMeuseMessageHandler.any_instance.expects(:publish_usage).never
        Codespaces::Billing::PrebuildStorageMeuseMessageHandler.any_instance.expects(:transform_usage)
        Codespaces::Billing::PrebuildStorageMeuseMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
      end
    end
  end
end unless GitHub.enterprise?
