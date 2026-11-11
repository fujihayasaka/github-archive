# typed: true
# frozen_string_literal: true

class Billing::Settings::ZuoraBillingInfoComponent < ApplicationComponent
  # system_arguments - optional Hash of [system arguments](https://primer.style/view-components/system-arguments) to
  #                    be applied to the outermost element.
  def initialize(target:, send_ga_event: nil, ga_category: nil, ga_action: nil, ga_label: nil, billing_contact: nil, **system_arguments)
    @target = target
    @send_ga_event = send_ga_event
    @ga_category = ga_category
    @ga_action = ga_action
    @ga_label = ga_label
    @system_arguments = system_arguments
    @container_class = @system_arguments.delete(:classes)
    @billing_contact = billing_contact
  end

  private

  attr_reader :target, :send_ga_event, :ga_category, :ga_action, :ga_label, :container_class, :system_arguments

  def render?
    GitHub.billing_enabled? && target.present?
  end

  delegate :region, :postal_code, :address1, :address2, :city, to: :billing_contact

  memoize def billing_contact
    @billing_contact.presence || target.billing_contact
  end

  def country_code
    billing_contact.country&.alpha3
  end
end
