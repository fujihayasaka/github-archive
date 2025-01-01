# typed: true
# frozen_string_literal: true

module Settings
  class SecuritySettingDialogComponent < ApplicationComponent
    renders_one :dialog_body

    def initialize(button_text:,
                   title:,
                   dialog_text: nil,
                   input_name:,
                   input_value:,
                   data_octo_click: nil,
                   data_octo_dimensions: nil,
                   dialog_button_text: nil,
                   button_aria_label: "",
                   button_scheme: :default)
      @button_text = button_text
      @title = title
      @dialog_text = dialog_text
      @input_name = input_name
      @input_value = input_value
      @data_octo_click = data_octo_click
      @data_octo_dimensions = data_octo_dimensions
      @dialog_button_text = dialog_button_text ? dialog_button_text : button_text
      @button_scheme = button_scheme
      @button_aria_label = button_aria_label
    end
  end
end
