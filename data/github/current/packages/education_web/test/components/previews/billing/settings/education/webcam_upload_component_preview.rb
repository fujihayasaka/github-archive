# typed: true
# frozen_string_literal: true

class Billing::Settings::Education::WebcamUploadComponentPreview < ViewComponent::Preview
  def default
    render(
      Billing::Settings::Education::WebcamUploadComponent.new(
        allow_file_upload: true,
        form_field_id: "webcam-upload",
      ),
    )
  end

  def with_form_wrapper
    render(
      Billing::Settings::Education::DeveloperPackApplicationFormComponent.new(
        form_errors: {},
        form_values: {
          form_variant: "initial_form",
        },
        user:,
      )
    )
  end

  private

  def user
    User.new(login: "BillingSettingsEdDevPackUser")
  end
end
