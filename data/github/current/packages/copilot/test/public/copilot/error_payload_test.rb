# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::ErrorPayloadTest < GitHub::TestCase
  test "nothing is set if nothing is passed" do
    payload = Copilot::ErrorPayload.new
    assert_equal({}, payload.normalize)
  end

  test "everything is set if everything is passed" do
    organization = Copilot::Organization.new(create(:copilot_for_business_enabled_organization))
    business = Copilot::Business.new(T.must(organization.organization_object.business))
    trial = create(:copilot_business_trial, :organization)
    configuration = create(:copilot_configuration, :business)
    editor_notification = create(:copilot_editor_notification, notification_id: Copilot::EditorNotification::COPILOT_NOTIFICATION_TYPES.keys.first.to_s)
    free_user = create(:copilot_free_user)
    seat = create(:copilot_seat)
    seat_assignment = seat.seat_assignment
    user = Copilot::User.new(create(:user))

    payload = Copilot::ErrorPayload.new(
      copilot_business: business,
      copilot_business_trial: trial,
      copilot_configuration: configuration,
      copilot_editor_notification: editor_notification,
      copilot_free_user: free_user,
      copilot_organization: organization,
      copilot_seat_assignment: seat_assignment,
      copilot_seat: seat,
      copilot_user: user
    )

    assert_equal(
      {
        "gh.business.id" => business.business_object.id,
        "gh.copilot.business_trial.id" => trial.id,
        "gh.copilot.business_trial.length" => trial.trial_length,
        "gh.copilot.business_trial.seat_count" => 0, # trial.seat_count will be deprecated soon
        "gh.copilot.business_trial.started_at" => trial.started_at,
        "gh.copilot.business_trial.ends_at" => trial.ends_at,
        "gh.copilot.business_trial.managing_user.id" => trial.managing_user_id,
        "gh.copilot.configuration.id" => configuration.id,
        "gh.copilot.editor_notification.id" => editor_notification.id,
        "gh.copilot.free_user.id" => free_user.id,
        "gh.copilot.free_user.type" => free_user.free_user_type,
        "gh.organization.id" => organization.organization_object.id,
        "gh.copilot.seat_assignment.id" => seat_assignment.id,
        "gh.copilot.seat_assignment.owner.type" => seat_assignment.owner_type,
        "gh.copilot.seat.id" => seat.id,
        "gh.user.id" => user.id
      },
      payload.normalize
    )
  end

  test "seat_assignment_owner_type is not set if owner type is nil" do
    sa = create(:copilot_seat_assignment, :organization)
    sa.update_columns(owner_type: nil)
    payload = Copilot::ErrorPayload.new(
      copilot_seat_assignment: sa
    )
    assert_equal(
      {
        "gh.copilot.seat_assignment.id" => sa.id
      },
      payload.normalize
    )
  end
end if GitHub.copilot_enabled?
