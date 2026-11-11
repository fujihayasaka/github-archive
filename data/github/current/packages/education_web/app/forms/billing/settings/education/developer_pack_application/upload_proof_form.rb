# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    module Education
      module DeveloperPackApplication
        class UploadProofForm < BaseForm
          FORM_FIELDS_FOR_THIS_PAGE = [
            Field.new(name: :proof_type, required: true),
            Field.new(name: :photo_proof, required: true),
          ].freeze

          PROOF_TYPE_OPTIONS = [
            "1. Dated school ID",
            "2. Dated official/unofficial transcript",
            "3. Dated enrollment letter on school letterhead",
            "4. Dated class schedule for the semester",
            "5. Dated syllabus for a class",
            "6. Dated receipt from bursar",
            "7. Dated scholarship/financial aid letter",
            "8. Other (Example: Screenshot of school portal)",
          ].freeze

          form do |upload_proof_form|
            T.bind(self, UploadProofForm)

            if applicant_is_teacher?
              upload_proof_form.text_field(
                name: :proof_type,
                classes: "d-none",
                label: nil,
                value: PROOF_TYPE_OPTIONS.first,
              )
            else
              upload_proof_form.action_menu(
                name: :proof_type,
                label: "Please select the type of academic enrollment proof you would like to provide",
                prompt: "Select one",
                required: true,
                validation_message: form_errors[:proof_type],
                dynamic_label: true,
                dynamic_label_prefix: "Select: ",
              ) do |menu|
                selected_proof = form_values[:proof_type]
                PROOF_TYPE_OPTIONS.each do |option|
                  menu.with_item(label: option, data: { value: option }, active: option == selected_proof)
                end
              end
            end

            upload_proof_form.hidden(name: :photo_proof, id: "photo_proof")
            existing_fields_to_forward(form: upload_proof_form)

            if far_from_campus_proof_required?
              submit_button(form: upload_proof_form)
            else
              submit_button(form: upload_proof_form, name: :submit, label: "Submit Application")
            end
          end

          private

          sig { returns(T::Boolean) }
          def far_from_campus_proof_required?
            form_values[:user_too_far_from_school] == "true"
          end

          sig { returns(T::Boolean) }
          def applicant_is_teacher?
            form_values[:application_type] == "faculty"
          end
        end
      end
    end
  end
end
