# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    module Education
      module DeveloperPackApplication
        class NewSchoolForm < BaseForm
          FORM_FIELDS_FOR_THIS_PAGE = [
            Field.new(name: :school_website),
            Field.new(name: :teacher_email_sample_address),
            Field.new(name: :student_email_sample_address),
            Field.new(name: :school_type, required: true),
            Field.new(name: :number_of_students),
            Field.new(name: :location_address),
            Field.new(name: :location_city, required: true),
            Field.new(name: :location_country, required: true),
            Field.new(name: :location_state_or_province),
          ].freeze

          form do |new_school_form|
            T.bind(self, NewSchoolForm)

            new_school_form.group(layout: :vertical) do |info_group|
              info_group.text_field(
                name: :school_website,
                label: "What is your school's website?",
              )

              info_group.text_field(
                name: :teacher_email_sample_address,
                label: "What academic email does your school provide to teachers?",
                placeholder: "name@teacher.yourschool.edu",
              )

              info_group.text_field(
                name: :student_email_sample_address,
                label: "What academic email does your school provide to students?",
                placeholder: "name@students.yourschool.edu",
              )

              info_group.select_list(
                name: :school_type,
                label: "How would you describe your school?",
                prompt: "Select one",
                required: true,
                validation_message: form_errors[:school_type],
              ) do |select|
                select.option(value: "higher_education", label: "Higher-education: university, college")
                select.option(value: "high_school", label: "High school")
                select.option(value: "informal", label: "Informal: bootcamp, career-training")
              end

              info_group.select_list(
                name: :number_of_students,
                label: "How many students are enrolled at your school?",
                prompt: "Select one",
              ) do |select|
                select.option(value: "100", label: "Less than 100")
                select.option(value: "500", label: "100 - 500")
                select.option(value: "1000", label: "500 - 1,000")
                select.option(value: "5000", label: "1,000 - 5,000")
                select.option(value: "10000", label: "5,000 - 10,000")
                select.option(value: "20000", label: "10,000 - 20,000")
                select.option(value: "30000", label: "20,000 - 30,000")
                select.option(value: "40000", label: "30,000 - 40,000")
                select.option(value: "50000", label: "40,000 - 50,000")
                select.option(value: "999999", label: "Over 50,000")
              end
            end

            new_school_form.separator

            new_school_form.group(layout: :vertical) do |location_group|
              location_group.text_field(
                name: :location_address,
                label: "Street address",
              )

              location_group.text_field(
                name: :location_city,
                label: "City",
                required: true,
                validation_message: form_errors[:location_city],
              )

              location_group.select_list(
                name: :location_country,
                label: "Country",
                prompt: "Select one",
                required: true,
                validation_message: form_errors[:location_country],
              ) do |select|
                ::TradeControls::Countries.marketing_targeted_countries.each do |name, alpha, _, _|
                  select.option(value: alpha, label: name)
                end
              end

              location_group.text_field(
                name: :location_state_or_province,
                label: "State, region, or province",
              )
            end

            existing_fields_to_forward(form: new_school_form)
            submit_button(form: new_school_form)
          end
        end
      end
    end
  end
end
