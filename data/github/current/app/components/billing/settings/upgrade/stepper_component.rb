# typed: true
# frozen_string_literal: true

class Billing::Settings::Upgrade::StepperComponent < ApplicationComponent

  DEFAULT_TYPE = :plan_upgrade
  TYPES = T.let([:plan_upgrade, :stepper_only, :manage_subscription].freeze, T::Array[Symbol])

  sig { returns T.any(Integer, String) }
  attr_reader :seats

  sig { returns Integer }
  attr_reader :min

  sig { returns Integer }
  attr_reader :max

  sig { returns String }
  attr_reader :form

  sig { returns String }
  attr_reader :min_error_message

  sig { returns String }
  attr_reader :max_error_message

  sig { returns T.nilable(String) }
  attr_reader :current_url

  sig { returns T::Boolean }
  attr_reader :show_label

  sig { returns String }
  attr_reader :label

  sig { returns String }
  attr_reader :param_name

  sig { returns String }
  attr_reader :name

  sig { returns T::Hash[Symbol, T.untyped] }
  attr_reader :system_arguments

  # Renders a seat stepper component
  # If type is :plan_upgrade, it will add the necessary ids and classes, that billing bundle JS expects
  sig do params(seats: T.any(Integer, String), min: Integer, max: Integer, form: String, current_url: T.nilable(String),
    label: String, show_label: T::Boolean, min_error_message: String, max_error_message: String, type: Symbol, param_name: String,
    name: String, system_arguments: T.untyped).void
  end
  def initialize(seats:, min:, max:, form:, current_url: nil, label: "seat", show_label: false, min_error_message: "",
    max_error_message: "", type: DEFAULT_TYPE, param_name: "seats", name: "seats", **system_arguments)
    @seats = seats
    @min = min
    @max = max
    @form = form
    @current_url = current_url
    @label = label
    @show_label = show_label
    @type = T.let(fetch_or_fallback(TYPES, type, DEFAULT_TYPE), Symbol)
    @min_error_message = min_error_message
    @max_error_message = max_error_message
    @param_name = param_name
    @name = name
    @system_arguments = system_arguments
    @system_arguments[:classes] = class_names("js-stepper", @system_arguments[:classes]) if @type == :plan_upgrade
  end

  sig { returns T::Boolean }
  def show_inline_errors?
    @type == :plan_upgrade || @type == :manage_subscription
  end

  sig { returns String }
  def stepper_label_classes
    return "unstyled-label" if @type == :plan_upgrade
    ""
  end

  sig { returns String }
  def stepper_label
    label.pluralize(seats)
  end

  sig { returns(T::Boolean) }
  def read_only?
    return false unless GitHub.flipper[:billing_upgrade_stepper_component_read_only_mode].enabled?

    min == max
  end

  renders_one :remove_seat_control, lambda { |**system_arguments|
    if @type == :manage_subscription
      system_arguments[:data] = {
        target: "manage-subscription.remove_seats",
        action: "click:manage-subscription#removeSeats"
      }.merge(system_arguments[:data] || {})
    end
    Primer::Beta::IconButton.new(
      **system_arguments,
      icon: :dash,
      classes: "rounded-right-0" + (@type == :plan_upgrade ? " js-decrease-seats-number" : ""),
      border_right: 0,
      px: 3,
      "aria-label": "Remove #{@label}")
  }

  renders_one :add_seat_control, lambda { |**system_arguments|
    if @type == :manage_subscription
      system_arguments[:data] = {
        target: "manage-subscription.add_seats",
        action: "click:manage-subscription#addSeats"
      }.merge(system_arguments[:data] || {})
    end
    Primer::Beta::IconButton.new(
      **system_arguments,
      icon: :plus,
      border_left: 0,
      px: 3,
      classes: "rounded-left-0" + (@type == :plan_upgrade ? " js-increase-seats-number" : ""),

      "aria-label": "Add #{@label}")
  }

  renders_one :context, lambda { |**system_arguments|
    system_arguments[:tag] ||= :div
    system_arguments[:color] ||= :subtle
    system_arguments[:font_size] ||= :small
    system_arguments[:mt] ||= 2

    Primer::Beta::Text.new(**system_arguments)
  }

  renders_one :input, lambda { |**system_arguments|
    if @type == :manage_subscription
      system_arguments[:data] = {
        target: "manage-subscription.seats",
        action: "input:manage-subscription#debouncedUpdatePrice change:manage-subscription#validateAndUpdatePrice"
      }.merge(system_arguments[:data] || {})
    elsif @type == :plan_upgrade
      system_arguments[:data] = {
        minimum: @min,
        maximum: @max,
        url: @current_url,
      }.merge(system_arguments[:data] || {})
      system_arguments[:test_selector] = "billing-seats-input" unless system_arguments[:test_selector]
    end

    if @type != :plan_upgrade
      system_arguments[:min] = @min unless system_arguments[:min]
      system_arguments[:max] = @max unless system_arguments[:max]
    end

    add_billing_js_classes_and_ids = @type == :plan_upgrade
    classes = "form-control billing-settings-stepper-input"
    if add_billing_js_classes_and_ids
      classes += " js-trial-upgrade-seats js-experiment-seats" # see observer in app/assets/modules/github/billing/upgrade-seats.ts
    end

    system_arguments[:name] = @name unless system_arguments[:name]

    Primer::BaseComponent.new(
      **system_arguments,
      tag: :input,
      type: :number,
      value: @seats,
      form: @form,
      "data-url-param-name": @param_name,
      "aria-label": "Number of #{@label.pluralize}",
      classes: classes,
      border_radius: 0,
      text_align: :center,
      style: system_arguments[:style] || "width:60px;",
      name: system_arguments[:name],
    )
  }
end
