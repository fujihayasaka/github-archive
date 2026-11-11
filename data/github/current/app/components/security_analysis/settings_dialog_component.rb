# typed: true
# frozen_string_literal: true

class SecurityAnalysis::SettingsDialogComponent < ApplicationComponent
  def initialize(
    summary_button_text:,
    confirm_button_text:,
    title:,
    warning_text: nil,
    dialog_text:,
    input_name:,
    input_value:,
    test_selector: nil,
    data_octo_click: nil,
    data_octo_dimensions: nil,
    scheme: :secondary,
    button_aria_label: "",
    disabled: false,
    checkbox_name: nil,
    checkbox_id: nil,
    checkbox_condition: nil,
    checkbox_label: nil,
    checkbox_description: nil)

    @summary_button_text = summary_button_text
    @confirm_button_text = confirm_button_text
    @title = title
    @warning_text = warning_text
    @dialog_text = dialog_text
    @input_name = input_name
    @input_value = input_value
    @test_selector = test_selector
    @data_octo_click = data_octo_click
    @data_octo_dimensions = data_octo_dimensions
    @scheme = scheme
    @button_aria_label = button_aria_label
    @disabled = disabled
    @checkbox_name = checkbox_name
    @checkbox_id = checkbox_id
    @checkbox_condition = checkbox_condition
    @checkbox_label = checkbox_label
    @checkbox_description = checkbox_description
  end

  def include_checkbox?
    !@checkbox_name.nil? && !@checkbox_id.nil? && !@checkbox_condition.nil? && !@checkbox_label.nil?
  end

  memoize def dialog_id
    SecureRandom.hex(4)
  end

  private

  def button_data_attr
    result = { "data-close-dialog-id": dialog_id }
    result.merge!("data-octo-click": @data_octo_click) if @data_octo_click
    result.merge!("data-octo-dimensions": "enabled:#{@data_octo_dimensions},location:settings") if @data_octo_dimensions
    result
  end
end
