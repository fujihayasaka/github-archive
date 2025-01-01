# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::Billing::PrebuildStorageVNextMessageHandlerTest < GitHub::TestCase
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

  context "#transform_usage" do
    test "puts data in expected format" do
      unique_billing_identifier = "Codespaces/PrebuildStorage/#{@billing_message.event_id}-#{@billing_entry.prebuild_plan_name}-#{@billing_entry.prebuild_template_guid}-#{@tracked_usage.formatted_sku_name}"
      handler = Codespaces::Billing::PrebuildStorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry)

      expected = {
        sku: "codespaces_prebuild_storage",
        quantity: @tracked_usage.computed_usage_in_gb_month,
        usage_at: Google::Protobuf::Timestamp.new(seconds: @billing_message.period_end.to_i, nanos: 0),
        source_uri: @billing_message.source_uri,
        entity: {
          customer_id: @owner.customer.id,
          organization_id: @billing_entry.repository&.organization_id,
          repo_id: @billing_entry.repository_id,
          actor_id: nil,
        },
        usage_uuid: GitHub::Billing::MeteredProduct.usage_uuid(unique_billing_identifier)
      }
      result = handler.send(:transform_usage)
      assert_equal expected, result
    end

    test "send appropriate fields when prebuild owned by enterprise" do
      member = create :user
      org = create :organization, admins: [member]
      repository = create :repository, owner: org
      enterprise = create :business, owners: [member], organizations: [org]
      prebuild_template = create(:codespace_prebuild_template, repository: repository)
      org.reload
      billing_entry = prebuild_template.billing_entry

      billing_message = build(
        :codespace_ephemeral_billing_message,
        :without_compute,
        codespace_plan_id: prebuild_template.plan.id,
        codespaces: [prebuild_template]
      )
      tracked_usage = billing_message.tracked_usages_for(billing_entry.prebuild_template_guid).find(&:is_storage?)
      handler = Codespaces::Billing::PrebuildStorageVNextMessageHandler.new(billing_message: billing_message, tracked_usage: tracked_usage, billing_entry: billing_entry)
      result = handler.send(:transform_usage)
      assert enterprise.customer_id
      assert org.id
      assert_equal(result[:entity][:customer_id], enterprise.customer_id)
      assert_equal(result[:entity][:organization_id], org.id)
      assert_nil(result[:entity][:actor_id])
    end
  end

  context "#perform" do
    test "calls additional methods if should_publish?" do
      Codespaces::Billing::PrebuildStorageVNextMessageHandler.any_instance.expects(:should_publish?).returns(true)
      Codespaces::Billing::PrebuildStorageVNextMessageHandler.any_instance.expects(:transform_usage)
      Codespaces::Billing::PrebuildStorageVNextMessageHandler.any_instance.expects(:publish_usage)

      Codespaces::Billing::PrebuildStorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
    end

    test "doesn't additional methods if the usage type if not should_publish?" do
      Codespaces::Billing::PrebuildStorageVNextMessageHandler.any_instance.expects(:should_publish?).returns(false)
      Codespaces::Billing::PrebuildStorageVNextMessageHandler.any_instance.expects(:transform_usage).never
      Codespaces::Billing::PrebuildStorageVNextMessageHandler.any_instance.expects(:publish_usage).never
      Codespaces::Billing::PrebuildStorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
    end

    context "if should_test_non_prod?" do
      test "does not log dev/ppe message if feature flag is disabled" do
        GitHub.flipper[:codespaces_billing_test_non_prod].disable
        @billing_message.stubs(:vscs_target).returns(:development)
        Codespaces::Billing::PrebuildStorageVNextMessageHandler.any_instance.expects(:publish_non_prod_usage).never
        Codespaces::Billing::PrebuildStorageVNextMessageHandler.any_instance.expects(:transform_usage).never
        Codespaces::Billing::PrebuildStorageVNextMessageHandler.any_instance.expects(:publish_usage).never
        Codespaces::Billing::PrebuildStorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
      end

      test "does not log dev/ppe message if it should not be published" do
        GitHub.flipper[:codespaces_billing_test_non_prod].enable
        @billing_message.stubs(:vscs_target).returns(:development)
        @billing_entry.stubs(:billable_owner).returns(nil)
        Codespaces::Billing::PrebuildStorageVNextMessageHandler.any_instance.expects(:publish_non_prod_usage).never
        Codespaces::Billing::PrebuildStorageVNextMessageHandler.any_instance.expects(:transform_usage).never
        Codespaces::Billing::PrebuildStorageVNextMessageHandler.any_instance.expects(:publish_usage).never
        Codespaces::Billing::PrebuildStorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
      end

      test "logs for dev/ppe if should normally publish & feature flag is on" do
        GitHub.flipper[:codespaces_billing_test_non_prod].enable
        @billing_message.stubs(:vscs_target).returns(:development)
        Codespaces::Billing::PrebuildStorageVNextMessageHandler.any_instance.expects(:publish_non_prod_usage)
        Codespaces::Billing::PrebuildStorageVNextMessageHandler.any_instance.expects(:publish_usage).never
        Codespaces::Billing::PrebuildStorageVNextMessageHandler.any_instance.expects(:transform_usage)
        Codespaces::Billing::PrebuildStorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
      end
    end
  end

  context "#publish_usage" do
    test "returns result to publish" do
      data = {
        test_data: true,
      }

      handler = Codespaces::Billing::PrebuildStorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry)
      result = handler.send(:publish_usage, data)

      assert_equal(result.hydro_topic, "billingplatform.v1.Usage")
      assert_equal data, result.hydro_payload

    end
  end

  context "#transform_usage_for_splunk" do
    test "transforms nested hash to flat and uses semconv keys" do
      data = {
        sku: "sku",
        quantity: "quantity",
        usage_at: Google::Protobuf::Timestamp.new(seconds: @billing_message.period_end.to_i, nanos: 0),
        source_uri: "source_uri",
        entity: {
          customer_id: "customer_id",
          organization_id: "organization_id",
          repo_id: "repo_id",
          actor_id: "actor_id",
        },
        usage_uuid: "usage_uuid",
      }

      expected = {
        "gh.codespaces.billing_message.product_sku_name" => "sku",
        "gh.codespaces.billing_message.quantity" => "quantity",
        "gh.codespaces.billing_message.usage_at.seconds" => @billing_message.period_end.to_i,
        "gh.codespaces.billing_message.usage_at.nanos" => 0,
        "gh.codespaces.billing_message.source_uri" => "source_uri",
        "gh.billing.customer.id" => "customer_id",
        "gh.org.id" => "organization_id",
        "gh.repo.id" => "repo_id",
        "gh.user.id" => "actor_id",
        "gh.codespaces.billing_message.usage_uuid" => "usage_uuid",
      }

      handler = Codespaces::Billing::PrebuildStorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry)
      result = handler.send(:transform_usage_for_splunk, data)
      assert_equal(result, expected)
    end
  end

  context "#should_publish?" do
    test "returns false if compute message" do
      tracked_usage = @billing_message.tracked_usages_for(@billing_entry.prebuild_template_guid).find(&:is_compute?)
      refute Codespaces::Billing::PrebuildStorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns false when billable owner is given free codespace usage" do
      GitHub.flipper[:codespaces_billing_free].enable(@billing_entry.billable_owner&.billable_owner)
      refute Codespaces::Billing::PrebuildStorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns false when billable owner is given free prebuild usage" do
      GitHub.flipper[:codespaces_prebuild_billing_free].enable(@billing_entry.billable_owner&.billable_owner)
      refute Codespaces::Billing::PrebuildStorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns true when billable owner is a user" do
      owner = create(:user)
      repo = create(:private_repository, owner: owner, from_example: :simple)

      prebuild_template = create(:codespace_prebuild_template, repository: repo)
      billing_entry = prebuild_template.billing_entry

      billing_message = build(
        :codespace_ephemeral_billing_message,
        :without_compute,
        codespace_plan_id: prebuild_template.plan.id,
        codespaces: [prebuild_template]
      )
      tracked_usage = billing_message.tracked_usages_for(billing_entry.prebuild_template_guid).find(&:is_storage?)
      assert Codespaces::Billing::PrebuildStorageVNextMessageHandler.new(billing_message:, tracked_usage:, billing_entry:).send(:should_publish?)
    end

    test "returns false when owner does not exist" do
      @billing_entry.stubs(:billable_owner).returns(nil)
      refute Codespaces::Billing::PrebuildStorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns false if computed_usage_in_gb_month isn't positive" do
      @tracked_usage.stubs(:computed_usage_in_gb_month).returns(0)
      refute Codespaces::Billing::PrebuildStorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end

    test "returns false if billing region isn't primary region" do
      prebuild_template = create(:codespace_prebuild_template, repository: @repo, location: "WestUs3")
      billing_entry = prebuild_template.billing_entry

      billing_message = build(
        :codespace_ephemeral_billing_message,
        :without_compute,
        codespace_plan_id: prebuild_template.plan.id,
        codespaces: [prebuild_template]
      )
      tracked_usage = billing_message.tracked_usages_for(billing_entry.prebuild_template_guid).find(&:is_storage?)
      refute Codespaces::Billing::PrebuildStorageVNextMessageHandler.new(billing_message: billing_message, tracked_usage: tracked_usage, billing_entry: billing_entry).send(:should_publish?)
    end

    test "otherwise returns true" do
      assert Codespaces::Billing::PrebuildStorageVNextMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).send(:should_publish?)
    end
  end
end unless GitHub.enterprise?
