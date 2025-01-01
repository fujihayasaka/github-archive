# typed: true
# frozen_string_literal: true

require "test_helper"

class Stafftools::VssSubscriptionEventsControllerTest < GitHub::IntegrationTestCase
  fixtures do
    @staff = create(:staff_admin_user)
    @non_staff_user = create(:user)
    @failed_event = create(:licensing_vss_subscription_event, :failed)
    @under_investigation_event = create(:licensing_vss_subscription_event, :under_investigation)
    @processed_event = create(:licensing_vss_subscription_event, :processed)
    @unprocessed_event = create(:licensing_vss_subscription_event, :unprocessed)
  end

  context "#index" do
    if GitHub.billing_enabled?
      test "renders a list of unsuccessful (failed or under investigation) events" do
        as @staff

        get "/stafftools/vss_subscription_events"

        assert_response 200
        assert_select "[data-test-selector='vss-subscription-event-#{@failed_event.id}']", count: 1
        assert_select "[data-test-selector='vss-subscription-event-#{@under_investigation_event.id}']", count: 1
        refute_select "[data-test-selector='vss-subscription-event-#{@processed_event.id}']"
        refute_select "[data-test-selector='vss-subscription-event-#{@unprocessed_event.id}']"
      end

      test "404s for non-staff" do
        as @non_staff_user

        get "/stafftools/vss_subscription_events"

        assert_response 404
      end
    else
      test "404s for when billing is disabled" do
        as @staff_user

        get "/stafftools/vss_subscription_events"

        assert_response 404
      end
    end
  end

  context "#perform" do
    if GitHub.billing_enabled?
      test "reprocesses the event" do
        as @staff

        Licensing::VssSubscriptionEventProcessingJob.expects(:perform_now).raises(StandardError.new("bang")).once

        put "/stafftools/vss_subscription_events/#{@failed_event.id}/perform"

        assert_redirected_to "/stafftools/vss_subscription_events"
        assert_equal "bang", flash[:error]
      end

      test "404s for non-staff" do
        as @non_staff_user

        Licensing::VssSubscriptionEventProcessingJob.expects(:perform_now).never

        put "/stafftools/vss_subscription_events/#{@failed_event.id}/perform"

        assert_response 404
      end
    else
      test "404s for when billing is disabled" do
        as @staff_user

        Licensing::VssSubscriptionEventProcessingJob.expects(:perform_now).never

        put "/stafftools/vss_subscription_events/#{@failed_event.id}/perform"

        assert_response 404
      end
    end
  end

  context "#investigate" do
    if GitHub.billing_enabled?
      test "updates the event's status to under investigation with a note" do
        as @staff

        put "/stafftools/vss_subscription_events/#{@failed_event.id}/investigate", params: { investigation_notes: "some issue link" }

        assert_redirected_to "/stafftools/vss_subscription_events"

        @failed_event.reload
        assert @failed_event.under_investigation?
        assert_equal "some issue link", @failed_event.investigation_notes
      end

      test "404s for non-staff" do
        as @non_staff_user

        put "/stafftools/vss_subscription_events/#{@failed_event.id}/investigate", params: { investigation_notes: "some issue link" }

        assert_response 404

        @failed_event.reload
        refute @failed_event.under_investigation?
        assert_nil @failed_event.investigation_notes
      end
    else
      test "404s for when billing is disabled" do
        as @staff_user

        put "/stafftools/vss_subscription_events/#{@failed_event.id}/investigate", params: { investigation_notes: "some issue link" }

        assert_response 404

        @failed_event.reload
        refute @failed_event.under_investigation?
        assert_nil @failed_event.investigation_notes
      end
    end
  end
end
