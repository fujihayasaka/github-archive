# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    module Education
      module DeveloperPackApplication
        class FarFromCampusProofForm < BaseForm
          FORM_FIELDS_FOR_THIS_PAGE = [
            Field.new(name: :far_from_campus_reason, required: true),
            Field.new(name: :far_from_campus_proof, required: true),
          ].freeze

          form do |far_from_campus_proof_form|
            T.bind(self, FarFromCampusProofForm)

            far_from_campus_proof_form.radio_button_group(
              name: :far_from_campus_reason,
              label: "Why are you not on campus?",
              required: true,
              validation_message: form_errors.slice(
                :far_from_campus_reason,
                :far_from_campus_proof,
              ).to_a.transpose.second&.to_sentence,
            ) do |radio_group|
              radio_group.radio_button(value: "sem_class_not_started", label: "This semester's classes have not yet started")
              radio_group.radio_button(value: "distant_course_work", label: "All coursework is via distance learning")
              radio_group.radio_button(value: "vpn", label: "I am using a VPN")
              radio_group.radio_button(value: "other", label: "Other:")
            end

            far_from_campus_proof_form.text_field(name: :other_reason_text, label: "Please provide a brief explanation")

            far_from_campus_proof_form.hidden(name: :far_from_campus_proof, id: "far_from_campus_proof")
            existing_fields_to_forward(form: far_from_campus_proof_form)
            submit_button(form: far_from_campus_proof_form, name: :submit, label: "Submit Application")
          end
        end
      end
    end
  end
end
