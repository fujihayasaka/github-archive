# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::Billing::DispatchCodespaceMessageTest < GitHub::TestCase
  include DogstatsTestHelpers
  include CodespacesPlanFixtures
  include GitHub::LoggerHelper

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:credit_card_user)
    @codespace = create(:codespace, owner: @user)
    @billing_entry = @codespace.billing_entry
    @billing_message = build(
      :codespace_ephemeral_billing_message,
      codespace_plan_id: @codespace.plan_id,
      codespaces: [@codespace],
    )
    @tracked_usages = @billing_message.tracked_usages_for(@billing_entry.codespace_guid)
    @org = create(:business_plus_organization)
    @org_repo = create(:private_repository, owner: @org)
    @org_codespace = create(:codespace, repository: @org_repo)
    @cw_codespace = create(:copilot_workspace, owner: @user)
    @cw_billing_entry = @cw_codespace.billing_entry
    @cw_billing_message = build(
      :codespace_ephemeral_billing_message,
      codespace_plan_id: @cw_codespace.plan_id,
      codespaces: [@cw_codespace],
    )
    @cw_tracked_usages = @cw_billing_message.tracked_usages_for(@cw_billing_entry.codespace_guid)
  end

  context "perform_health_checks" do
    context "spammy billable owner" do
      test "does not add a datadog entry for billable owners that are not spammy", skip_enterprise: true do
        Codespaces::Billing::DispatchCodespaceMessage.new(billing_message: @billing_message, tracked_usages: @tracked_usages, billing_entry: @billing_entry).send(:perform_health_checks)

        assert_equal 0, GitHub.dogstats.increments("codespaces.process_billing_message.spammy_billable_owner", tags: ["vscs_target:production"]).length
      end

      test "does not add a datadog entry for owners that are spammy when the org is not", skip_enterprise: true do
        @org_codespace.owner.mark_as_spammy

        Codespaces::Billing::DispatchCodespaceMessage.new(billing_message: @billing_message, tracked_usages: @tracked_usages, billing_entry: @billing_entry).send(:perform_health_checks)

        assert_equal 0, GitHub.dogstats.increments("codespaces.process_billing_message.spammy_billable_owner", tags: ["vscs_target:production"]).length
      end

      test "adds a datadog entry for billable owners that are spammy", skip_enterprise: true do
        @codespace.owner.mark_as_spammy

        Codespaces::Billing::DispatchCodespaceMessage.new(billing_message: @billing_message, tracked_usages: @tracked_usages, billing_entry: @billing_entry).send(:perform_health_checks)

        assert_equal 1, GitHub.dogstats.increments("codespaces.process_billing_message.spammy_billable_owner", tags: ["vscs_target:production"]).length
      end
    end

    context "accessibility" do
      context "when codespace is accessible" do
        test "notifies GitHub.dogstats.increment with 'codespaces.accessibility_check', tags: ['is_accessible:yes']" do
          Codespaces::Billing::DispatchCodespaceMessage.new(billing_message: @billing_message, tracked_usages: @tracked_usages, billing_entry: @billing_entry).send(:perform_health_checks)

          assert_equal 1, GitHub.dogstats.increments("codespaces.accessibility_check", tags: ["is_accessible:yes", "vscs_target:#{@billing_message.vscs_target}"]).length
        end

        test "returns true" do
          assert Codespaces::Billing::DispatchCodespaceMessage.new(billing_message: @billing_message, tracked_usages: @tracked_usages, billing_entry: @billing_entry).send(:perform_health_checks)
        end
      end

      context "when codespace is not accessible" do
        test "sends event: codespaces.inaccessible_codespace" do
          not_org_member = create(:user)
          @org_codespace.owner = not_org_member
          @org_codespace.save!

          billing_message = build(
            :codespace_ephemeral_billing_message,
            :without_compute,
            codespace_plan_id: @org_codespace.plan_id,
            codespaces: [@org_codespace]
          )

          GlobalInstrumenter.expects(:instrument).
            once.with("codespaces.inaccessible_codespace", { codespace_id: @org_codespace.id })

          Codespaces::Billing::DispatchCodespaceMessage.new(billing_message: billing_message, tracked_usages: billing_message.tracked_usages_for(@org_codespace.guid), billing_entry: @org_codespace.billing_entry).send(:perform_health_checks)
        end

        test "notifies GitHub.dogstats.increment with 'codespaces.accessibility_check', tags: ['is_accessible:no']" do
          not_org_member = create(:user)
          @org_codespace.owner = not_org_member
          @org_codespace.save!

          billing_message = build(
            :codespace_ephemeral_billing_message,
            :without_compute,
            codespace_plan_id: @org_codespace.plan_id,
            codespaces: [@org_codespace]
          )

          Codespaces::Billing::DispatchCodespaceMessage.new(billing_message: billing_message, tracked_usages: billing_message.tracked_usages_for(@org_codespace.guid), billing_entry: @org_codespace.billing_entry).send(:perform_health_checks)

          assert_equal 1, GitHub.dogstats.increments("codespaces.accessibility_check", tags: ["is_accessible:no", "vscs_target:#{billing_message.vscs_target}"]).length
        end

        test "deletes the codespace" do
          disable_feature_flag(:codespaces_pause_deletions_inaccessible)
          not_org_member = create(:user)
          @org_codespace.owner = not_org_member
          @org_codespace.save!
          FakeVSOServer.environments << { "id" => @org_codespace.guid, "state" => Codespaces::Vscs::State::AVAILABLE }

          billing_message = build(
            :codespace_ephemeral_billing_message,
            :without_compute,
            codespace_plan_id: @org_codespace.plan_id,
            codespaces: [@org_codespace]
          )

          assert_predicate Codespace.where(id: @org_codespace.id), :exists?

          perform_enqueued_jobs do # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
            Codespaces::Billing::DispatchCodespaceMessage.new(billing_message: billing_message, tracked_usages: billing_message.tracked_usages_for(@org_codespace.guid), billing_entry: @org_codespace.billing_entry).send(:perform_health_checks)
          end

          refute_predicate Codespace.where(id: @org_codespace.id), :exists?
        end

        test "if deleted, it does not send event: codespaces.inaccessible_codespace" do
          not_org_member = create(:user)
          @org_codespace.owner = not_org_member
          @org_codespace.save!

          billing_message = build(
            :codespace_ephemeral_billing_message,
            :without_compute,
            codespace_plan_id: @org_codespace.plan_id,
            codespaces: [@org_codespace]
          )
          billing_entry = @org_codespace.billing_entry
          @org_codespace.delete

          GlobalInstrumenter.expects(:instrument).
            never.with("codespaces.inaccessible_codespace", { codespace_id: @org_codespace.id })

          Codespaces::Billing::DispatchCodespaceMessage.new(billing_message: @billing_message, tracked_usages: @tracked_usages, billing_entry: billing_entry).send(:perform_health_checks)
        end
      end
    end
  end

  context "#valid_billing_message?" do

    context "when codespace has been soft deleted" do

      test "returns true for a restored codespace" do
        Codespaces::SoftDelete.call(@codespace)

        Codespaces::Billing::DispatchCodespaceMessage.new(billing_message: @billing_message, tracked_usages: @tracked_usages, billing_entry: @billing_entry).send(:valid_billing_message?)

        Codespaces::Restore.call(@codespace)
        assert Codespaces::Billing::DispatchCodespaceMessage.new(billing_message: @billing_message, tracked_usages: @tracked_usages, billing_entry: @billing_entry).send(:valid_billing_message?)
      end
    end
  end

  context "#dispatch" do
    context "without vnext" do
      test "calls each dispatcher for each usage report" do
        @tracked_usages.each do |tracked_usage|
          Codespaces::Billing::ComputeAnalyticsMessageHandler.expects(:call).with(tracked_usage: tracked_usage, billing_entry: @billing_entry, billing_message: @billing_message)
          Codespaces::Billing::ComputeMeuseMessageHandler.expects(:call).with(tracked_usage: tracked_usage, billing_entry: @billing_entry, billing_message: @billing_message)
          Codespaces::Billing::StorageAnalyticsMessageHandler.expects(:call).with(tracked_usage: tracked_usage, billing_entry: @billing_entry, billing_message: @billing_message)
          Codespaces::Billing::StorageMeuseMessageHandler.expects(:call).with(tracked_usage: tracked_usage, billing_entry: @billing_entry, billing_message: @billing_message)
          Codespaces::Billing::CopilotWorkspaceMessageHandler.expects(:call).with(tracked_usage: tracked_usage, billing_entry: @billing_entry, billing_message: @billing_message)
        end
        Codespaces::Billing::DispatchCodespaceMessage.new(billing_message: @billing_message, tracked_usages: @tracked_usages, billing_entry: @billing_entry).send(:dispatch)
      end

      test "returns values from handlers in correct format, removing nil" do
        value = "value we care about"
        another_value = "another"
        second_value = "second"
        another_second_value = "another second"
        Codespaces::Billing::ComputeAnalyticsMessageHandler.expects(:call).returns(nil).twice
        Codespaces::Billing::ComputeMeuseMessageHandler.expects(:call).returns(value).then.returns(second_value).twice
        Codespaces::Billing::StorageAnalyticsMessageHandler.expects(:call).returns(nil).twice
        Codespaces::Billing::StorageMeuseMessageHandler.expects(:call).returns(another_value).then.returns(another_second_value).twice
        result = Codespaces::Billing::DispatchCodespaceMessage.new(billing_message: @billing_message, tracked_usages: @tracked_usages.slice(0, 2), billing_entry: @billing_entry).send(:dispatch)
        assert_same_elements(result, [value, another_value, second_value, another_second_value])
      end
    end

    context "with vnext" do
      test "calls each dispatcher for each usage report" do
        @user.billing_customer.create_billing_platform_enabled_product(codespaces: true)
        @tracked_usages.each do |tracked_usage|
          Codespaces::Billing::ComputeAnalyticsMessageHandler.expects(:call).with(tracked_usage: tracked_usage, billing_entry: @billing_entry, billing_message: @billing_message)
          Codespaces::Billing::ComputeVNextMessageHandler.expects(:call).with(tracked_usage: tracked_usage, billing_entry: @billing_entry, billing_message: @billing_message)
          Codespaces::Billing::StorageAnalyticsMessageHandler.expects(:call).with(tracked_usage: tracked_usage, billing_entry: @billing_entry, billing_message: @billing_message)
          Codespaces::Billing::StorageVNextMessageHandler.expects(:call).with(tracked_usage: tracked_usage, billing_entry: @billing_entry, billing_message: @billing_message)
          Codespaces::Billing::CopilotWorkspaceMessageHandler.expects(:call).with(tracked_usage: tracked_usage, billing_entry: @billing_entry, billing_message: @billing_message)
        end
        Codespaces::Billing::DispatchCodespaceMessage.new(billing_message: @billing_message, tracked_usages: @tracked_usages, billing_entry: @billing_entry).send(:dispatch)
      end

      test "returns values from handlers in correct format, removing nil" do
        @user.billing_customer.create_billing_platform_enabled_product(codespaces: true)
        value = "value we care about"
        another_value = "another"
        second_value = "second"
        another_second_value = "another second"
        Codespaces::Billing::ComputeAnalyticsMessageHandler.expects(:call).returns(nil).twice
        Codespaces::Billing::ComputeVNextMessageHandler.expects(:call).returns(value).then.returns(second_value).twice
        Codespaces::Billing::StorageAnalyticsMessageHandler.expects(:call).returns(nil).twice
        Codespaces::Billing::StorageVNextMessageHandler.expects(:call).returns(another_value).then.returns(another_second_value).twice
        result = Codespaces::Billing::DispatchCodespaceMessage.new(billing_message: @billing_message, tracked_usages: @tracked_usages, billing_entry: @billing_entry).send(:dispatch)
        assert_same_elements(result, [value, another_value, second_value, another_second_value])
      end
    end

    context "with CW codespaces" do
      test "returns values from handlers in correct format, removing nil" do
        value = "value we care about"
        second_value = "second"
        Codespaces::Billing::ComputeAnalyticsMessageHandler.expects(:call).returns(nil).twice
        Codespaces::Billing::ComputeMeuseMessageHandler.expects(:call).returns(nil).twice
        Codespaces::Billing::StorageAnalyticsMessageHandler.expects(:call).returns(nil).twice
        Codespaces::Billing::StorageMeuseMessageHandler.expects(:call).returns(nil).twice
        Codespaces::Billing::CopilotWorkspaceMessageHandler.expects(:call).returns(value).then.returns(second_value).twice
        result = Codespaces::Billing::DispatchCodespaceMessage.new(billing_message: @cw_billing_message, tracked_usages: @cw_tracked_usages.slice(0, 2), billing_entry: @cw_billing_entry).send(:dispatch)
        assert_same_elements(result, [value, second_value])
      end
    end
  end

  context "#perform" do
    test "returns early if the billing entry is not a codespace billing entry" do
      prebuild_template = create(:codespace_prebuild_template)
      billing_entry = prebuild_template.billing_entry
      billing_message = build(
        :codespace_ephemeral_billing_message,
        :without_compute,
        codespace_plan_id: prebuild_template.plan.id,
        codespaces: [prebuild_template],
      )
      tracked_usages = billing_message.tracked_usages_for(billing_entry.prebuild_template_guid)

      Codespaces::Billing::DispatchCodespaceMessage.any_instance.expects(:valid_billing_message?).never
      Codespaces::Billing::DispatchCodespaceMessage.new(billing_message: billing_message, tracked_usages: tracked_usages, billing_entry: billing_entry).perform
    end


    test "will call dispatch if the billing message is valid" do
      Codespaces::Billing::DispatchCodespaceMessage.any_instance.expects(:dispatch)
      Codespaces::Billing::DispatchCodespaceMessage.new(billing_message: @billing_message, tracked_usages: @tracked_usages, billing_entry: @billing_entry).perform
    end

    test "will call dispatch if the user is spammy" do
      @codespace.owner.mark_as_spammy
      Codespaces::Billing::DispatchCodespaceMessage.any_instance.expects(:dispatch)
      Codespaces::Billing::DispatchCodespaceMessage.new(billing_message: @billing_message, tracked_usages: @tracked_usages, billing_entry: @billing_entry).perform

    end

    test "will call dispatch if codespace is inaccessible" do
      not_org_member = create(:user)
      @org_codespace.owner = not_org_member
      @org_codespace.save!

      billing_message = build(
        :codespace_ephemeral_billing_message,
        :without_compute,
        codespace_plan_id: @org_codespace.plan_id,
        codespaces: [@org_codespace]
      )
      Codespaces::Billing::DispatchCodespaceMessage.any_instance.expects(:dispatch)
      Codespaces::Billing::DispatchCodespaceMessage.new(billing_message: billing_message, tracked_usages: billing_message.tracked_usages_for(@org_codespace.guid), billing_entry: @org_codespace.billing_entry).perform
    end

    test "will not call dispatch if the billing message is invalid" do
      original_codespace_creation_date = 2.days.ago
      codespace = create(:codespace, created_at: original_codespace_creation_date)
      codespace.billing_entry.update!(created_at: original_codespace_creation_date, codespace_deprovisioned_at: 121.minutes.ago)
      billing_message = build(
        :codespace_ephemeral_billing_message,
        codespace_plan_id: codespace.plan_id,
        codespaces: [codespace],
        period_start: 120.minutes.ago,
        period_end: 60.minutes.ago
      )

      codespace.delete

      Codespaces::Billing::DispatchCodespaceMessage.any_instance.expects(:dispatch).never
      Codespaces::Billing::DispatchCodespaceMessage.new(billing_message: billing_message, tracked_usages: billing_message.tracked_usages_for(codespace.guid), billing_entry: codespace.billing_entry).perform
    end
  end
end unless GitHub.enterprise?
