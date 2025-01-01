# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::Billing::DispatchPrebuildMessageTest < GitHub::TestCase
  include CodespacesPlanFixtures
  include DogstatsTestHelpers

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    geos = [
      "UsWest",
    ]
    @template_location = "WestUs2"
    @org = create(:organization, :with_azure_subscription)
    # with_azure_subscription required to give billing_entry a billing_customer value
    repo = create(:repository, owner: @org, from_example: :refs_test)
    @prebuild_configuration = create(:codespace_prebuild_configuration, with_geos: geos, devcontainer_path: ".devcontainer/devcontainer.json", repository: repo)
    @prebuild_template = create(
      :codespace_prebuild_template,
      codespace_prebuild_configuration_id: @prebuild_configuration.id,
      repository: @prebuild_configuration.repository,
      location: @template_location,
      devcontainer_path: @prebuild_configuration.devcontainer_path,
    )
    @billing_entry = @prebuild_template.billing_entry
    @billing_message = build(
      :codespace_ephemeral_billing_message,
      :without_compute,
      codespace_plan_id: @prebuild_template.plan.id,
      codespaces: [@prebuild_template],
    )
    @tracked_usages = @billing_message.tracked_usages_for(@billing_entry.prebuild_template_guid)
    GitHub.flipper[:codespaces_check_prebuild_config_valid_before_billing].disable(@prebuild_configuration.repository)
    GitHub.flipper[:codespaces_delete_invalid_prebuild_billing_entry].disable(@prebuild_configuration.repository)
  end

  context "#valid_billing_message?" do
    test "returns false if billing entry's deprovisioned_at date is before the billing_message's time range" do
      original_creation_date = 2.days.ago
      @billing_entry.update!(created_at: original_creation_date, prebuild_deleted_at: 121.minutes.ago)
      billing_message = build(
        :codespace_ephemeral_billing_message,
        :without_compute,
        codespace_plan_id: @prebuild_template.plan.id,
        codespaces: [@prebuild_template],
        period_start: 120.minutes.ago,
        period_end: 60.minutes.ago
      )

      @prebuild_template.delete

      refute Codespaces::Billing::DispatchPrebuildMessage.new(billing_message: billing_message, tracked_usages: billing_message.tracked_usages_for(@prebuild_template.guid), billing_entry: @billing_entry).send(:valid_billing_message?)
    end

    test "returns true if billing entry's deprovisioned_at date is after the billing_message's time range" do
      original_creation_date = 2.days.ago
      @billing_entry.update!(created_at: original_creation_date, prebuild_deleted_at: 10.minutes.ago)
      billing_message = build(
        :codespace_ephemeral_billing_message,
        :without_compute,
        codespace_plan_id: @prebuild_template.plan.id,
        codespaces: [@prebuild_template],
        period_start: 120.minutes.ago,
        period_end: 60.minutes.ago
      )

      @prebuild_template.delete

      assert Codespaces::Billing::DispatchPrebuildMessage.new(billing_message: billing_message, tracked_usages: billing_message.tracked_usages_for(@prebuild_template.guid), billing_entry: @billing_entry).send(:valid_billing_message?)
    end

    test "it returns true for a non deleted prebuild" do
      original_creation_date = 2.days.ago
      @billing_entry.update!(created_at: original_creation_date, prebuild_deleted_at: nil)
      billing_message = build(
        :codespace_ephemeral_billing_message,
        :without_compute,
        codespace_plan_id: @prebuild_template.plan.id,
        codespaces: [@prebuild_template],
        period_start: 120.minutes.ago,
        period_end: 60.minutes.ago
      )

      assert Codespaces::Billing::DispatchPrebuildMessage.new(billing_message: billing_message, tracked_usages: billing_message.tracked_usages_for(@prebuild_template.guid), billing_entry: @billing_entry).send(:valid_billing_message?)
    end
  end

  context "#dispatch" do
    context "without vnext" do
      test "calls each dispatcher for each usage report" do
        @tracked_usages.each do |tracked_usage|
          Codespaces::Billing::PrebuildStorageMeuseMessageHandler.expects(:call).with(tracked_usage: tracked_usage, billing_entry: @billing_entry, billing_message: @billing_message)
          Codespaces::Billing::PrebuildStorageAnalyticsMessageHandler.expects(:call).with(tracked_usage: tracked_usage, billing_entry: @billing_entry, billing_message: @billing_message)
        end
        Codespaces::Billing::DispatchPrebuildMessage.new(billing_message: @billing_message, tracked_usages: @tracked_usages, billing_entry: @billing_entry).send(:dispatch)
      end

      test "returns values from handlers in correct format, removing nil" do
        value = "value we care about"
        another_value = "something else we care about"
        Codespaces::Billing::PrebuildStorageMeuseMessageHandler.expects(:call).returns(value).then.returns(nil).twice
        Codespaces::Billing::PrebuildStorageAnalyticsMessageHandler.expects(:call).returns(another_value).then.returns(nil).twice
        result = Codespaces::Billing::DispatchPrebuildMessage.new(billing_message: @billing_message, tracked_usages: @tracked_usages, billing_entry: @billing_entry).send(:dispatch)
        assert_equal(result, [value, another_value])
      end
    end

    context "with vnext" do
      test "calls each dispatcher for each usage report" do
        @org.billing_customer.create_billing_platform_enabled_product(codespaces: true)
        @tracked_usages.each do |tracked_usage|
          Codespaces::Billing::PrebuildStorageVNextMessageHandler.expects(:call).with(tracked_usage: tracked_usage, billing_entry: @billing_entry, billing_message: @billing_message)
          Codespaces::Billing::PrebuildStorageAnalyticsMessageHandler.expects(:call).with(tracked_usage: tracked_usage, billing_entry: @billing_entry, billing_message: @billing_message)
        end
        Codespaces::Billing::DispatchPrebuildMessage.new(billing_message: @billing_message, tracked_usages: @tracked_usages, billing_entry: @billing_entry).send(:dispatch)
      end

      test "returns values from handlers in correct format, removing nil" do
        @org.billing_customer.create_billing_platform_enabled_product(codespaces: true)
        value = "value we care about"
        another_value = "something else we care about"
        Codespaces::Billing::PrebuildStorageVNextMessageHandler.expects(:call).returns(value).then.returns(nil).twice
        Codespaces::Billing::PrebuildStorageAnalyticsMessageHandler.expects(:call).returns(another_value).then.returns(nil).twice
        result = Codespaces::Billing::DispatchPrebuildMessage.new(billing_message: @billing_message, tracked_usages: @tracked_usages, billing_entry: @billing_entry).send(:dispatch)
        assert_equal(result, [value, another_value])
      end
    end
  end

  context "#perform" do
    test "returns early if the billing entry is not a prebuild template billing entry" do
      codespace = create(:codespace)
      billing_entry = codespace.billing_entry
      billing_message = build(
        :codespace_ephemeral_billing_message,
        codespace_plan_id: codespace.plan_id,
        codespaces: [codespace],
      )
      tracked_usages = billing_message.tracked_usages_for(billing_entry.codespace_guid)

      Codespaces::Billing::DispatchPrebuildMessage.any_instance.expects(:valid_billing_message?).never
      Codespaces::Billing::DispatchPrebuildMessage.new(billing_message: billing_message, tracked_usages: tracked_usages, billing_entry: billing_entry).perform
    end

    test "will call dispatch if the billing message is valid" do
      Codespaces::Billing::DispatchPrebuildMessage.any_instance.expects(:valid_billing_message?).returns(true)
      Codespaces::Billing::DispatchPrebuildMessage.any_instance.expects(:dispatch)
      Codespaces::Billing::DispatchPrebuildMessage.new(billing_message: @billing_message, tracked_usages: @tracked_usages, billing_entry: @billing_entry).perform
    end

    test "will not call dispatch if the billing message is invalid" do
      Codespaces::Billing::DispatchPrebuildMessage.any_instance.expects(:valid_billing_message?).returns(false)
      Codespaces::Billing::DispatchPrebuildMessage.any_instance.expects(:dispatch).never
      Codespaces::Billing::DispatchPrebuildMessage.new(billing_message: @billing_message, tracked_usages: @tracked_usages, billing_entry: @billing_entry).perform
    end

    test "will not call dispatch if prebuild configuration has already been deleted" do
      @prebuild_configuration.delete

      GitHub.flipper[:codespaces_check_prebuild_config_valid_before_billing].enable(@prebuild_template.repository)
      Codespaces::Billing::DispatchPrebuildMessage.any_instance.expects(:dispatch).never
      Codespaces::DeletePrebuildTemplatesJob.expects(:perform_later)
      Codespaces::Billing::DispatchPrebuildMessage.call(billing_message: @billing_message, tracked_usages: @tracked_usages, billing_entry: @billing_entry)
    end

    test "will not call dispatch if prebuild configuration location does not match" do
      @prebuild_configuration.update_locations(locations: ["EuropeWest"])

      GitHub.flipper[:codespaces_check_prebuild_config_valid_before_billing].enable(@prebuild_template.repository)
      Codespaces::Billing::DispatchPrebuildMessage.any_instance.expects(:dispatch).never
      Codespaces::DeletePrebuildTemplatesJob.expects(:perform_later)
      Codespaces::Billing::DispatchPrebuildMessage.call(billing_message: @billing_message, tracked_usages: @tracked_usages, billing_entry: @billing_entry)
    end

    test "will not call dispatch if configuration is invalid" do
      @prebuild_configuration.update_locations(locations: ["EuropeWest"])
      GitHub.flipper[:codespaces_check_prebuild_config_valid_before_billing].enable(@prebuild_template.repository)
      GitHub.flipper[:codespaces_delete_invalid_prebuild_billing_entry].enable(@prebuild_template.repository)

      Codespaces::Billing::DispatchPrebuildMessage.any_instance.expects(:dispatch).never
      Codespaces::DeletePrebuildTemplatesJob.expects(:perform_later)
      Codespaces::Billing::DispatchPrebuildMessage.call(billing_message: @billing_message, tracked_usages: @tracked_usages, billing_entry: @billing_entry)
    end

    test "will call dispatch and look up prebuild config if config id is nil" do
      @prebuild_template.update!(codespace_prebuild_configuration_id: nil)

      GitHub.flipper[:codespaces_check_prebuild_config_valid_before_billing].enable(@prebuild_template.repository)
      Codespaces::Billing::DispatchPrebuildMessage.any_instance.expects(:dispatch)
      Codespaces::DeletePrebuildTemplatesJob.expects(:perform_later).never
      Codespaces::Billing::DispatchPrebuildMessage.new(billing_message: @billing_message, tracked_usages: @tracked_usages, billing_entry: @billing_entry).perform
    end
  end
end unless GitHub.enterprise?
