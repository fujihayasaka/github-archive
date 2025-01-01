# typed: true
# frozen_string_literal: true

require "test_helper"

class PrebuildTemplateBillingEntry < GitHub::TestCase
  include DogstatsTestHelpers
  include CodespacesPlanFixtures
  fixtures do
    @repo = create(:repository)
    @prebuild_template = create(:codespace_prebuild_template, repository: @repo)
  end

  context "validations" do
    test "ensure that we have a valid billable owner, prebuild template guid and prebuild template id" do
      prebuild_template_billing_entry = Codespaces::PrebuildTemplateBillingEntry.new

      refute prebuild_template_billing_entry.valid?
      refute_nil prebuild_template_billing_entry.errors[:billable_owner]
      refute_nil prebuild_template_billing_entry.errors[:prebuild_template_id]
      refute_nil prebuild_template_billing_entry.errors[:prebuild_template_guid]
    end

    test "passes with required fields" do
      owner = create :user
      repository = create :repository
      prebuild_template_billing_entry = Codespaces::PrebuildTemplateBillingEntry.new \
        prebuild_template_guid: @prebuild_template.guid,
        prebuild_template_id: @prebuild_template.id,
        billable_owner: @repo.owner,
        repository: repository

      assert_predicate  prebuild_template_billing_entry, :valid?
    end

    test "testing if prebuild_template is equal to billing entry's prebuild template" do
      prebuild_template_billing_entry = Codespaces::PrebuildTemplateBillingEntry.create!(
        billable_owner: @repo.owner,
        repository: @repo,
        prebuild_template_guid: @prebuild_template.guid,
        prebuild_template_id: @prebuild_template.id,
        prebuild_plan_name: "test",
        prebuild_created_at: @prebuild_template.created_at,
      )

      assert_equal @prebuild_template, prebuild_template_billing_entry.prebuild_template

    end
  end

  context "#latest scope" do
    test "it returns the latest billing entry for a given guid" do
      # create an additional billing entry
      prebuild_template_billing_entry = Codespaces::PrebuildTemplateBillingEntry.create!(
        billable_owner: @repo.owner,
        repository: @repo,
        prebuild_template_guid: @prebuild_template.guid,
        prebuild_template_id: @prebuild_template.id,
        prebuild_plan_name: "test",
        prebuild_created_at: @prebuild_template.created_at,
      )

      latest_prebuild_template_billing_entry = Codespaces::PrebuildTemplateBillingEntry.latest(@prebuild_template.guid)
      assert_equal  prebuild_template_billing_entry, latest_prebuild_template_billing_entry
    end
  end
end
