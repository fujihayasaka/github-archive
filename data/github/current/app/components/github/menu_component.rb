# typed: true
# frozen_string_literal: true

module GitHub
  class MenuComponent < ApplicationComponent
    renders_one :header
    renders_one :extra
    renders_one :summary
    renders_one :body

    ALIGN_DEFAULT = :left
    ALIGN_RIGHT = :right
    ALIGN_OPTIONS = [ALIGN_DEFAULT, ALIGN_RIGHT]

    def initialize(
      items: [],
      title: nil,
      text: nil,
      filterable: false,
      src: nil,
      src_error_msg: nil,
      preload: false,
      align: ALIGN_DEFAULT,
      filter_placeholder: nil,
      onselect: nil,
      onselected: nil,
      modal_class: nil,
      js_filterable: false,
      js_filterable_id: "assigns-filter-field",
      input_id: nil,
      **system_arguments
    )
      @items = items
      @title = title
      @text = text
      @filterable = filterable
      @src = src
      @src_error_msg = src_error_msg
      @preload = preload
      @align = fetch_or_fallback(ALIGN_OPTIONS, align, ALIGN_DEFAULT)
      @filter_placeholder = filter_placeholder
      @onselect = onselect
      @onselected = onselected
      @modal_class = modal_class
      @js_filterable = js_filterable
      @js_filterable_id = js_filterable_id
      @input_id = input_id

      @system_arguments = system_arguments
      @system_arguments[:tag] = :details
      @system_arguments[:display] = :inline_block
      @system_arguments[:position] = :relative if @align == ALIGN_RIGHT
      @system_arguments[:id] = @system_arguments[:id] || "details-#{id}"
      @system_arguments[:classes] = class_names(
        "details-reset",
        "details-overlay",
        system_arguments[:classes]
      )
      @details_id = @system_arguments[:id]
    end

    memoize def id
      SecureRandom.hex(3)
    end

    def default_summary
      GitHub::MenuSummaryComponent.new(
        classes: "btn btn-sm select-menu-button",
        text: replaceable? ? @text : (@text || @title),
        menu: self)
    end

    def default_selection_text
      @items.find { |item| item.checked && item.try(:replace_text).present? }&.replace_text
    end

    memoize def replaceable?
      @items.any? { |item| item.try(:replace_text).present? }
    end

    def details_menu_class_names
      class_names(
        "SelectMenu",
        "SelectMenu--hasFilter" => @filterable,
        "right-0" => @align == ALIGN_RIGHT
      )
    end

    def modal_class_names
      class_names(
        "SelectMenu-modal",
        @modal_class
      )
    end

    def input_filterable_class_names
      if @js_filterable
        class_names("SelectMenu-input", "form-control", "js-filterable-field")
      else
        class_names("width-full", "form-control")
      end
    end
  end
end
