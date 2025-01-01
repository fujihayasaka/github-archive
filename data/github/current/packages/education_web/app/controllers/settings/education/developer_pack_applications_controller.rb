# typed: strict
# frozen_string_literal: true

class Settings::Education::DeveloperPackApplicationsController < ApplicationController
  FORM_FIELDS_MAPPING = T.let({
    "initial_form" =>
      Billing::Settings::Education::DeveloperPackApplication::InitialForm::FORM_FIELDS_FOR_THIS_PAGE,
    "new_school_form" =>
      Billing::Settings::Education::DeveloperPackApplication::NewSchoolForm::FORM_FIELDS_FOR_THIS_PAGE,
    "upload_proof_form" =>
      Billing::Settings::Education::DeveloperPackApplication::UploadProofForm::FORM_FIELDS_FOR_THIS_PAGE,
    "far_from_campus_proof_form" =>
      Billing::Settings::Education::DeveloperPackApplication::FarFromCampusProofForm::FORM_FIELDS_FOR_THIS_PAGE,
  }.freeze, T::Hash[String, T::Array[Billing::Settings::Education::DeveloperPackApplication::BaseForm::Field]])

  include Settings::ControllerMethods
  include Settings::Education::DeveloperPackApplications::SharedControllerMethods

  depends_on_clusters(
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:show],
  )

  sig { void }
  def show
    render_form_page(initial_form_values: {})
  end

  sig { void }
  def create
    if form_valid?
      if continuing_application?
        render_form_page
      else
        process_application
      end
    else
      render_partial_with_errors
    end
  end

  private

  sig { returns(T.untyped) }
  def suggested_schools
    results = schools_client.get_schools(github_user_verified_emails:, ip_address: request.remote_ip)

    if results.data && results.error.nil?
      results.data["schools"] || []
    else
      []
    end
  end

  sig { returns(T::Array[String]) }
  def github_user_verified_emails
    current_user.emails.verified.pluck(:email)
  end

  sig { params(initial_form_values: T.nilable(T::Hash[Symbol, T.nilable(String)])).void }
  def render_form_page(initial_form_values: nil)
    new_form_values = initial_form_values || form_values.to_h

    locals = {
      form_errors: {},
      form_values: new_form_values,
      user: current_user,
      suggested_schools:,
    }

    # rubocop:disable GitHub/RailsControllerRenderLiteral
    render(partial: "education/developer_pack_applications/form", locals:)
    # rubocop:enable GitHub/RailsControllerRenderLiteral
  end

  sig { void }
  def process_application
    processor_result = Education::DeveloperPackApplication::Processor.call(
      user: current_user,
      form_values: form_values.to_h,
    )

    if processor_result.success?
      flash[:notice] = "Your application has been submitted."
      redirect_to settings_user_billing_path
    else
      flash[:error] = processor_result.error.message
      redirect_to settings_user_billing_path
    end
  end

  sig { void }
  def render_partial_with_errors
    locals = {
      form_errors:,
      form_values: form_values.to_h,
      user: current_user,
      suggested_schools:,
    }

    # rubocop:disable GitHub/RailsControllerRenderLiteral
    render(partial: "education/developer_pack_applications/form", locals:)
    # rubocop:enable GitHub/RailsControllerRenderLiteral
  end

  sig { returns(ActionController::Parameters) }
  memoize def form_values
    params.require(:dev_pack_form).permit(
      :application_type,
      :camera_required,
      :email_domains,
      :far_from_campus_proof,
      :far_from_campus_proof_input,
      :far_from_campus_reason,
      :form_variant,
      :location_address,
      :location_city,
      :location_country,
      :location_state_or_province,
      :new_school,
      :number_of_students,
      :other_reason_text,
      :override_distance_limit,
      :photo_proof,
      :photo_proof_input,
      :proof_type,
      :school_email,
      :school_name,
      :school_type,
      :school_website,
      :selected_school_id,
      :student_email_sample_address,
      :teacher_email_sample_address,
      :two_factor_required,
      :user_too_far_from_school,
    )
  end

  sig { returns(T::Boolean) }
  def continuing_application?
    params[:continue].present?
  end

  sig { returns(T::Boolean) }
  def new_school_form_submission?
    form_values[:new_school].present?
  end

  sig { returns(T::Boolean) }
  def form_valid?
    form_errors.blank?
  end

  sig { returns(T::Hash[Symbol, T::Array[String]]) }
  memoize def form_errors
    form_fields = FORM_FIELDS_MAPPING.fetch(form_values[:form_variant], [])

    form_fields.each_with_object({}) do |field, errors|
      next unless field.required?

      if form_values[field.name].blank?
        errors[field.name] = "this field is required"
      end
    end
  end
end
