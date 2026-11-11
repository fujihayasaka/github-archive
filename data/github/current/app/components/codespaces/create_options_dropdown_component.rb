# typed: true
# frozen_string_literal: true

class Codespaces::CreateOptionsDropdownComponent < ApplicationComponent
  attr_reader :codespace, :create_button_text, :default_sku, :hide_advanced_options_button

  def initialize(codespace:, create_button_text:, default_sku:, hide_advanced_options_button: false)
    @codespace = codespace
    @create_button_text = create_button_text
    @default_sku = default_sku
    @hide_advanced_options_button = hide_advanced_options_button
  end
end
