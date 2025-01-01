# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    module Education
      module DeveloperPackApplication
        class BaseForm < ApplicationForm
          include ActionView::Helpers::UrlHelper
          include ActionView::Context

          def initialize(form_errors: {}, form_values:, user:, suggested_schools: nil)
            @form_errors = form_errors
            @form_values = form_values
            @user = user
            @suggested_schools = suggested_schools
          end

          private

          attr_reader :form_errors, :form_values, :user, :suggested_schools

          def existing_fields_to_forward(form:)
            form_variant = form.form.class.name.demodulize.underscore.to_sym

            fields_for_form = if form_variant == :initial_form
              InitialForm::FORM_FIELDS_FOR_THIS_PAGE
            elsif form_variant == :new_school_form
              NewSchoolForm::FORM_FIELDS_FOR_THIS_PAGE
            elsif form_variant == :upload_proof_form
              UploadProofForm::FORM_FIELDS_FOR_THIS_PAGE
            elsif form_variant == :far_from_campus_proof_form
              FarFromCampusProofForm::FORM_FIELDS_FOR_THIS_PAGE
            end

            form_values.each do |name, value|
              next if fields_for_form.map(&:name).include?(name.to_sym)

              form.hidden(name:, value:)
            end

            form.hidden(name: :form_variant, value: form_variant)
          end

          def submit_button(form:, label: "Continue", name: :continue)
            form.submit(
              name:,
              scheme: :primary,
              label:,
              float: :right,
              mt: 2,
              id: "js-developer-pack-application-submit-button",
              data: name == :submit ? { turbo: false } : {},
            )
          end

          def webcam_upload_fields(form:, field_name:)
            form.text_field(name: "#{field_name}_input".to_sym, label: nil, classes: "d-none")
          end

          def allow_file_upload?
            new_school? || form_values[:camera_required] == "false"
          end

          def new_school?
            form_values[:new_school] == "true"
          end

          class Field
            attr_reader :name

            def initialize(name:, required: false)
              @name = name
              @required = required
            end

            def required?
              @required
            end
          end
        end
      end
    end
  end
end
