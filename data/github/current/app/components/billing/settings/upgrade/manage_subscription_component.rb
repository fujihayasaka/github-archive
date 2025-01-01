# typed: true
# frozen_string_literal: true

class Billing::Settings::Upgrade::ManageSubscriptionComponent < ApplicationComponent

  EMDASH = "\u{2014}"

  sig { returns String }
  attr_reader :form_action

  sig { returns String }
  attr_reader :form_id

  sig { returns String }
  attr_reader :price_url

  sig { returns T::Boolean }
  attr_reader :can_manage_seats

  sig { returns String }
  attr_reader :cost_per_seat

  sig { returns String }
  attr_reader :cost_per_seat_label

  sig { returns String }
  attr_reader :current_payment

  sig { returns String }
  attr_reader :current_seats_label

  sig { returns T::Boolean }
  attr_reader :has_unlimited_seats

  sig { returns String }
  attr_reader :manage_seats_label

  sig { returns String }
  attr_reader :new_seats_payment

  sig { returns String }
  attr_reader :next_payment

  sig { returns String }
  attr_reader :next_payment_label

  sig { returns Symbol }
  attr_reader :open_edit_mode_param

  sig { returns String }
  attr_reader :payment_decrease

  sig { returns String }
  attr_reader :payment_due

  sig { returns String }
  attr_reader :payment_due_notice

  sig { returns String }
  attr_reader :payment_increase

  sig { returns String }
  attr_reader :payment_term_label

  sig { returns String }
  attr_reader :sales_tax_notice

  sig { returns String }
  attr_reader :total_seats_label

  sig { returns String }
  attr_reader :update_seats_label

  sig { returns T::Hash[Symbol, T.untyped] }
  attr_reader :system_arguments

  sig { returns(T.nilable(Business)) }
  attr_reader :business

  sig do params(
    form_action: String,
    form_id: String,
    price_url: String,
    # optional
    can_manage_seats: T::Boolean,
    cost_per_seat: String,
    cost_per_seat_label: String,
    current_payment: String,
    current_seats_label: String,
    has_unlimited_seats: T::Boolean,
    manage_seats_label: String,
    new_seats_payment: String,
    next_payment: String,
    next_payment_label: String,
    open_edit_mode_param: Symbol,
    payment_decrease: String,
    payment_due: String,
    payment_due_notice: String,
    payment_increase: String,
    payment_term_label: String,
    sales_tax_notice: String,
    total_seats_label: String,
    update_seats_label: String,
    business: T.nilable(Business),
    # kwargs
    system_arguments: Primer::SystemArgumentsValue
  ).void
  end
  def initialize(
    form_action:,
    form_id:,
    price_url:,
    # optional
    can_manage_seats: false,
    cost_per_seat: "",
    cost_per_seat_label: "Cost per seat",
    current_payment: "",
    current_seats_label: "",
    has_unlimited_seats: false,
    manage_seats_label: "Manage seats",
    new_seats_payment: "",
    next_payment: "",
    next_payment_label: "Next payment",
    open_edit_mode_param: :manage_seats,
    payment_decrease: "",
    payment_due: EMDASH,
    payment_due_notice: "",
    payment_increase: "",
    payment_term_label: "Monthly payment",
    sales_tax_notice: "",
    total_seats_label: "Total Seats",
    update_seats_label: "Update seats",
    business: nil,
    **system_arguments)
    @form_action = form_action
    @form_id = form_id
    @price_url = price_url
    # optional
    @can_manage_seats = can_manage_seats
    @cost_per_seat = cost_per_seat
    @cost_per_seat_label = cost_per_seat_label
    @current_payment = current_payment
    @current_seats_label = current_seats_label
    @has_unlimited_seats = has_unlimited_seats
    @manage_seats_label = manage_seats_label
    @new_seats_payment = new_seats_payment
    @next_payment = next_payment
    @next_payment_label = next_payment_label
    @open_edit_mode_param = open_edit_mode_param
    @payment_decrease = payment_decrease
    @payment_due = payment_due
    @payment_due_notice = payment_due_notice
    @payment_increase = payment_increase
    @payment_term_label = payment_term_label
    @sales_tax_notice = sales_tax_notice
    @total_seats_label = total_seats_label
    @update_seats_label = update_seats_label
    @business = business

    # Allow all overrides besides tag
    @system_arguments = system_arguments
    @system_arguments[:tag] = :"manage-subscription"
    @system_arguments[:classes] = class_names(
      "Box-title",
      system_arguments[:classes]
    )
    @system_arguments[:flex] = 1 unless system_arguments[:flex]
    @system_arguments[:my] = 2 unless system_arguments[:my]
    @system_arguments[:font_size] = :normal unless system_arguments[:font_size]
    @system_arguments[:color] = :default unless system_arguments[:color]
    @system_arguments[:data] = {
      "price-url": price_url
    }.merge(T.cast(system_arguments[:data], T.nilable(Hash)) || {})
  end

  memoize def trade_screening_error_data
    helpers.trade_screening_cannot_proceed_error_data(target: business, check_for_current_user: true)
  end

  renders_one :payment_method, lambda { |**system_arguments|
    system_arguments[:my] = 1 unless system_arguments[:my]
    Primer::BaseComponent.new(**system_arguments, tag: :div)
  }

  renders_many :hidden_form_fields, lambda { |**system_arguments|
    Primer::BaseComponent.new(**system_arguments, tag: :input, type: :hidden, autocomplete: "off")
  }

  renders_one :stepper_component, lambda { |**system_arguments|
    system_arguments[:my] = 2 unless system_arguments[:my]
    Billing::Settings::Upgrade::StepperComponent.new(**system_arguments, type: :manage_subscription)
  }
end
