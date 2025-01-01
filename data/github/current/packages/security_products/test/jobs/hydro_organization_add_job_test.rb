# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroOrganizationAddJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include HydroTestHelpers

  fixtures do
    # referencing the job class forces it to load, so it can be looked up by queue name
    @queue = HydroOrganizationAddJob.queue_name
    @schema = "github.enterprise_account.v0.OrganizationAdd"

    @admin = create :user
    @org = create :organization, plan: GitHub::Plan.business_plus
    @member = create(:user)
    @org.add_member(@member)
    @business = create :business, organizations: [@org], owners: [@admin]
  end

  test "kicks off organization add job" do
    message = {
      organization: Hydro::EntitySerializer.organization(@org),
      enterprise: Hydro::EntitySerializer.business(@business),
      actor: Hydro::EntitySerializer.user(@admin),
      new_organization: false,
      enterprise_trial: false,
    }

    assert_enqueued_jobs 1, only: OrganizationAddJob do
      perform_hydro_message_job(message, schema: @schema, queue: @queue)
    end
  end

  test "raises error and retries if organization doesn't exist" do
    HydroOrganizationAddJob.any_instance.expects(:retry).once.with(
      responds_with(
        :message,
        "Organization with ID #{@org.id} not found, retrying",
      ),
      delay: 2.0,
    )

    message = {
      organization: Hydro::EntitySerializer.organization(@org),
    }

    @org.destroy

    assert_enqueued_jobs 0, only: OrganizationAddJob do
      perform_hydro_message_job(message, schema: @schema, queue: @queue)
    end
  end

  test "silently stops the job after max number of retries" do
    HydroOrganizationAddJob.any_instance.expects(:retry).never
    HydroMessageJob.any_instance.stubs(:retries).returns(10)

    message = {
      organization: Hydro::EntitySerializer.organization(@org),
    }

    @org.destroy

    assert_enqueued_jobs 0, only: OrganizationAddJob do
      perform_hydro_message_job(message, schema: @schema, queue: @queue)
    end
  end
end
