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
    only: [:new],
  )

  sig { void }
  def new
    render_form_page
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

  sig { void }
  def render_form_page
    new_form_values = if action_name == "new"
      initial_form_values
    else
      form_values.to_h
    end

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
    result = Education::DeveloperPackApplication::Processor.call(
      user: current_user,
      form_values: form_values.to_h,
      ip_address: request.remote_ip,
    )

    if result.duplicate_photo?
      form_errors[:photo_proof] = [T.must(result.error.message)]
      form_values[:form_variant] = "upload_proof_form"
      render_partial_with_errors
    elsif result.missing_far_from_campus_proof?
      # Provided manually because the real validation errors in this case are really wordy.
      form_errors[:far_from_campus_reason] = [
        "Please upload an image to help us understand why you are so far from campus.",
      ]
      form_values[:form_variant] = "far_from_campus_proof_form"
      render_partial_with_errors
    else
      # rubocop:disable GitHub/RailsControllerRenderLiteral
      render(partial: "education/developer_pack_applications/result", locals: { result: })
      # rubocop:enable GitHub/RailsControllerRenderLiteral
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
      :browser_location,
      :camera_required,
      :email_domains,
      :far_from_campus_proof,
      :far_from_campus_proof_input,
      :far_from_campus_reason,
      :form_variant,
      :latitude,
      :location_address,
      :location_city,
      :location_country,
      :location_shared,
      :location_state_or_province,
      :longitude,
      :new_school,
      :number_of_students,
      :octo_cookie_content,
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
      :utm_content,
      :utm_source,
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
      next if field.name == :proof_type && form_values[:application_type] == "faculty"

      if field.name == :photo_proof
        errors[field.name] = "this field is required" if photo_proof_invalid?
      elsif form_values[field.name].blank?
        errors[field.name] = "this field is required"
      end
    end
  end

  sig { returns(T::Boolean) }
  def photo_proof_invalid?
    photo_proof_value = form_values[:photo_proof]

    # photo_proof comes in as stringified JSON
    if photo_proof_value.is_a?(String)
      begin
        photo_proof_value = JSON.parse(photo_proof_value)
      rescue JSON::ParserError
        # if it's not valid JSON, treat as if photo wasn't provided
        photo_proof_value = ""
      end
    end

    photo_proof_value.blank? ||
      (photo_proof_value.is_a?(Hash) && photo_proof_value.dig("image").blank?)
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def initial_form_values
    {
      utm_source: params[:utm_source],
      utm_content: params[:utm_content],
      octo_cookie_content: cookies["_octo"],
    }
  end
end
