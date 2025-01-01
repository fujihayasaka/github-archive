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

          form do |upload_proof_form|
            T.bind(self, UploadProofForm)

            upload_proof_form.select_list(
              name: :proof_type,
              label: "Please select the type of proof you would like to provide",
              prompt: "Select one",
              required: true,
              validation_message: form_errors.slice(:proof_type, :photo_proof).to_a.transpose.second&.to_sentence,
            ) do |select|
              [
                "1. Dated school ID - Good",
                "2. Dated official/unofficial transcript - Fair",
                "3. Dated enrollment letter on school letterhead - Fair",
                "4. Dated class schedule for the semester - Poor",
                "5. Dated syllabus for a class - Poor",
                "6. Dated receipt from bursar - Poor",
                "7. Dated scholarship/financial aid letter - Poor",
                "8. Other (Example: Screenshot of school portal) - Poor",
              ].each do |option|
                select.option(value: option, label: option)
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
        end
      end
    end
  end
end
