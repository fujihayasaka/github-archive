# typed: true
# frozen_string_literal: true

# This component is deprecated; please use `CodeScanning::AlertListActionMenuComponent` instead
# unless your menu has filtering or tabs.
# See discussion at https://github.com/github/code-scanning/issues/13071 for more details.
class CodeScanning::AlertSelectMenuComponent < ApplicationComponent

  attr_reader :id, :caption, :header, :data_path, :options

  # Either options or data_path must be provided
  def initialize(
    id:,
    caption:,
    header:,
    data_path: nil,
    options: nil,
    no_right_padding: false,
    clear_path: nil,
    show_clear: false,
    clear_text: nil,
    will_have_tabs: false,
    additional_classes: ""
  )
    @id = id
    @caption = caption
    @header = header
    @data_path = data_path
    @options = options
    @no_right_padding = no_right_padding
    @clear_path = clear_path
    @show_clear = show_clear
    @clear_text = clear_text.nil? ? "Clear #{@caption.downcase.pluralize}" : clear_text
    @will_have_tabs = will_have_tabs
    @additional_classes = additional_classes
  end

  def deferred?
    @data_path.present?
  end
end
