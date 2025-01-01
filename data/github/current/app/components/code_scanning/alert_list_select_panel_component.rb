# typed: true
# frozen_string_literal: true

# CodeScanning::AlertListSelectPanelComponent is for drop-down menus that
# require a filter bar. For those which don't require filtering, use
# CodeScanning::AlertListActionMenuComponent instead.
class CodeScanning::AlertListSelectPanelComponent < ApplicationComponent
  attr_reader :caption, :header, :data_path, :select_variant, :list_only

  sig { returns(T.nilable(T::Array[T::Hash[Symbol, T.untyped]])) }
  attr_reader :options

  # Either options or data_path must be provided.
  # Set list_only to true if you're using this component to return data
  # to be asynchronously populated into an existing menu.
  sig do
    params(
      caption: String,
      header: String,
      list_only: T::Boolean,
      data_path: T.nilable(String),
      options: T.nilable(T::Array[T::Hash[Symbol, T.untyped]]),
      no_right_padding: T::Boolean,
      clear_path: T.nilable(String),
      show_clear: T::Boolean,
      clear_text: T.nilable(String),
      test_selector: T.nilable(String),
      select_variant: Symbol,
    ).void
  end
  def initialize(
    caption:,
    header:,
    list_only: false,
    data_path: nil,
    options: nil,
    no_right_padding: false,
    clear_path: nil,
    show_clear: false,
    clear_text: nil,
    test_selector: nil,
    select_variant: :single
  )
    @caption = caption
    @header = header
    @list_only = list_only
    @data_path = data_path
    @options = options
    @no_right_padding = no_right_padding
    @clear_path = clear_path
    @show_clear = show_clear
    @clear_text = clear_text.nil? ? "Clear #{@caption.downcase.pluralize}" : clear_text
    @test_selector = test_selector
    @select_variant = select_variant
  end
end
