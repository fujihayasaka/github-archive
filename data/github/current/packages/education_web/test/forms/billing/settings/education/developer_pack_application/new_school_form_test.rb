# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  module Settings
    module Education
      module DeveloperPackApplication
        class NewSchoolFormTest < GitHub::TestCase
          include GitHub::ComponentTestHelpers

          setup { skip if GitHub.enterprise? }

          test "renders text field radio buttons" do
            form_errors = { location_city: "can't be blank" }
            form_values = { "other_key" => "other_value" }
            user = create(:user)

            render_primer_form_inline(
              scope: :dev_pack_form,
              url: Rails.application.routes.url_helpers.settings_education_developer_pack_applications_path,
              data: { turbo: true },
            ) do |form|
              NewSchoolForm.new(form, form_errors:, form_values:, user:)
            end

            assert_selector "select[aria-required='true'][name='dev_pack_form[location_country]']"
            assert_selector "input[name='dev_pack_form[location_address]']"
            assert_selector(
              "primer-text-field:has(input[invalid='true'][name='dev_pack_form[location_city]'])",
              text: "can't be blank",
            )
            assert_selector(
              "input[value='other_value'][type='hidden'][name='dev_pack_form[other_key]']",
              visible: :hidden,
            )
          end
        end
      end
    end
  end
end
