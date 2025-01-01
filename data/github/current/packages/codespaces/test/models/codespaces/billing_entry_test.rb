# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesBillingEntryTest < GitHub::TestCase
  fixtures do
    @codespace = create(:codespace)
  end

  context "validations" do
    test "ensure that we have a valid billable/codespace owner, codespace guid and plan name" do
      billing_entry = Codespaces::BillingEntry.new

      refute billing_entry.valid?
      refute_nil billing_entry.errors[:billable_owner]
      refute_nil billing_entry.errors[:codespace_owner]
      refute_nil billing_entry.errors[:codespace_guid]
      refute_nil billing_entry.errors[:codespace_plan_name]
    end

    test "passes with required fields" do
      owner = create :user
      repository = create :repository
      billing_entry = Codespaces::BillingEntry.new \
        codespace_guid: SecureRandom.uuid,
        codespace_plan_name: "a-great-plan-#{SecureRandom.uuid}",
        billable_owner: owner,
        codespace_owner: owner,
        repository: repository

      assert_predicate billing_entry, :valid?
    end
  end

  context "codespace association" do
    test "returns the associated codespace if it exists" do
      entry = @codespace.billing_entry
      assert_equal @codespace, entry.codespace
    end

    test "is nil if the codespace has been deleted" do
      entry = @codespace.billing_entry
      assert_equal @codespace, entry.codespace

      @codespace.delete

      assert_nil entry.reload.codespace
    end
  end

  context "#latest scope" do
    test "it returns the latest billing entry for a given guid" do
      # create an additional billing entry
      billing_entry = Codespaces::BillingEntry.create!(
        codespace: @codespace,
        billable_owner: @codespace.billable_owner,
        codespace_owner: @codespace.owner,
        repository: @codespace.repository,
        codespace_guid: @codespace.guid,
        codespace_plan_name: @codespace.plan.name,
      )

      latest_billing_entry = Codespaces::BillingEntry.latest(@codespace.guid)
      assert_equal billing_entry, latest_billing_entry
    end
  end

  context "#latest_created_before" do
    test "it returns the latest billing entry created before a given timestamp" do
      initial_billing_entry = @codespace.billing_entry

      # make a billing entry from 2 days ago
      # note: order here matters since Codespaces::BillingEntry.latest relies on the `id` for determining
      # the lastest billing entry

      expected_billing_entry = Codespaces::BillingEntry.new(
        codespace: @codespace,
        billable_owner: @codespace.billable_owner,
        codespace_owner: @codespace.owner,
        repository: @codespace.repository,
        codespace_guid: @codespace.guid,
        codespace_plan_name: @codespace.plan.name,
      )

      Timecop.travel(2.days.ago) do
        expected_billing_entry.save!
      end

      # make a billing entry that's effective 5 minutes ago
      latest_billing_entry = Codespaces::BillingEntry.new(
              codespace: @codespace,
              billable_owner: @codespace.billable_owner,
              codespace_owner: @codespace.owner,
              repository: @codespace.repository,
              codespace_guid: @codespace.guid,
              codespace_plan_name: @codespace.plan.name,
            )
      Timecop.travel(5.minutes.ago) do
        latest_billing_entry.save!
      end

      assert_equal latest_billing_entry, Codespaces::BillingEntry.latest(@codespace.guid)
      assert_equal expected_billing_entry, Codespaces::BillingEntry.latest_created_before(@codespace.guid, 1.day.ago)
      assert_same_elements [initial_billing_entry, expected_billing_entry, latest_billing_entry],
        Codespaces::BillingEntry.where(codespace_guid: @codespace.guid).to_a
    end
  end
end
