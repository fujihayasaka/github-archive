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
            Field.new(name: :number_of_students, required: true),
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

              info_group.action_menu(
                name: :school_type,
                label: "How would you describe your school?",
                required: true,
                validation_message: form_errors[:school_type],
                dynamic_label: true,
                dynamic_label_prefix: "Select: ",
              ) do |menu|
                selected_type = form_values[:school_type]
                menu.with_item(label: "Higher-education: university, college", data: { value: "higher_education" }, active: "higher_education" == selected_type)
                menu.with_item(label: "High school", data: { value: "high_school" }, active: "high_school" == selected_type)
                menu.with_item(label: "Informal: bootcamp, career-training", data: { value: "informal" }, active: "informal" == selected_type)
              end

              info_group.action_menu(
                name: :number_of_students,
                label: "How many students are enrolled at your school?",
                required: true,
                validation_message: form_errors[:number_of_students],
                dynamic_label: true,
                dynamic_label_prefix: "Select: ",
              ) do |menu|
                selected_count = form_values[:number_of_students]
                menu.with_item(label: "Less than 100", data: { value: "100" }, active: "100" == selected_count)
                menu.with_item(label: "100 - 500", data: { value: "500" }, active: "500" == selected_count)
                menu.with_item(label: "500 - 1,000", data: { value: "1000" }, active: "1000" == selected_count)
                menu.with_item(label: "1,000 - 5,000", data: { value: "5000" }, active: "5000" == selected_count)
                menu.with_item(label: "5,000 - 10,000", data: { value: "10000" }, active: "10000" == selected_count)
                menu.with_item(label: "10,000 - 20,000", data: { value: "20000" }, active: "20000" == selected_count)
                menu.with_item(label: "20,000 - 30,000", data: { value: "30000" }, active: "30000" == selected_count)
                menu.with_item(label: "30,000 - 40,000", data: { value: "40000" }, active: "40000" == selected_count)
                menu.with_item(label: "40,000 - 50,000", data: { value: "50000" }, active: "50000" == selected_count)
                menu.with_item(label: "Over 50,000", data: { value: "999999" }, active: "999999" == selected_count)
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

              location_group.action_menu(
                name: :location_country,
                label: "Country",
                required: true,
                validation_message: form_errors[:location_country],
                dynamic_label: true,
                dynamic_label_prefix: "Select: ",
              ) do |menu|
                selected_country = form_values[:location_country]
                ::TradeControls::Countries.marketing_targeted_countries.each do |name, alpha, _, _|
                  menu.with_item(label: name, data: { value: alpha }, active: alpha == selected_country)
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
