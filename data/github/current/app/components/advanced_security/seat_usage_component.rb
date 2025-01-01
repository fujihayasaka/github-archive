# typed: true
# frozen_string_literal: true

# Display details of the number of seats used and available for Advanced Security.
# Typically a meter is shown to indicate usage, but that's not shown in the unlimited case.
#
# This component also makes banner_* methods available to the enclosing template/component
# which can be used to determine whether a banner should be shown and what its message should be.
# Banners are not rendered directly in this component, since that approach offers less
# flexibility about layout.
class AdvancedSecurity::SeatUsageComponent < ApplicationComponent
  attr_reader :allowance_exceeded, :entity_licenses, :other_entities_licenses

  def initialize(
    # The first arg is set by the caller in the render call ...
    size: :default,

    # ... the rest are populated by kwargs_for

    consumed_licenses:,
    purchased_licenses:,
    # if this component is used for a business-owned org, this number is
    # how many that org is using as opposed to the full business total
    entity_licenses: nil,
    unlimited: false
  )
    # legacy licenses might have nil here; treat that as unlimited
    purchased_licenses = purchased_licenses || 0

    @consumed_licenses = consumed_licenses
    @purchased_licenses = purchased_licenses

    if entity_licenses.nil?
      @is_billable_entity = true
      @entity_licenses = consumed_licenses
      @other_entities_licenses = 0
    else
      @is_billable_entity = false
      @entity_licenses = entity_licenses
      @other_entities_licenses = consumed_licenses - entity_licenses
    end

    @unlimited = unlimited
    @allowance_exceeded = !unlimited && (consumed_licenses > purchased_licenses)
    @at_allowance_limit = !unlimited && (consumed_licenses == purchased_licenses)
    @size = size
  end

  # Generate the correct SeatUsageComponent.new keyword arguments for an entity which includes
  # Configurable::AdvancedSecurityBilling
  def self.kwargs_for(entity)
    license = entity.advanced_security_license
    kwargs = {
      consumed_licenses: license.consumed_seats,
      purchased_licenses: license.seats,
      unlimited: license.unlimited_seats?,
    }

    unless entity.advanced_security_billable_entity?
      kwargs[:entity_licenses] = entity.advanced_security_seats_used
    end

    kwargs
  end

  def available_licenses
    return "unlimited" if @unlimited

    @purchased_licenses - @consumed_licenses
  end

  def consumed_licenses_percent
    return 0 if @purchased_licenses <= 0
    percent = (@consumed_licenses.to_f / @purchased_licenses).round(2)
    (percent * 100).to_i
  end

  def entity_licenses_percent
    return 0 if @purchased_licenses <= 0
    percent = (@entity_licenses.to_f / @purchased_licenses).round(2)
    (percent * 100).to_i
  end

  def other_entities_licenses_percent
    return 0 if @purchased_licenses <= 0
    percent = (@other_entities_licenses.to_f / @purchased_licenses).round(2)
    (percent * 100).to_i
  end

  # This component provides banner details which the enclosing template/component can use.
  # These aren't rendered directly in this component itself, since this prevents the banner
  # being rendered in a different location in the UI.

  def banner_required?
    @allowance_exceeded || @at_allowance_limit
  end

  def banner_message
    return "" if @unlimited
    return "" if !@allowance_exceeded && !@at_allowance_limit

    prefix = @is_billable_entity ? "You are" : "Your enterprise is"
    suffix = if @allowance_exceeded
      "using #{ pluralize(number_with_delimiter(@consumed_licenses), "license") }, " +
      "exceeding #{@is_billable_entity ? "your" : "the"} paid seat limit of #{number_with_delimiter(@purchased_licenses)}."
    else
      "at capacity for licenses."
    end

    "#{prefix} #{suffix}"
  end

  def banner_arguments
    {
      icon: @allowance_exceeded ? :stop : :alert,
      scheme: @allowance_exceeded ? :danger : :warning,
    }
  end

  private

  def billable_entity?
    @is_billable_entity
  end

  def value_text
    unused = @purchased_licenses - @consumed_licenses
    unused = if unused < 0
      "#{ pluralize(-unused, "license") } over limit"
    elsif unused == 0
      "no free licenses remaining"
    else
      "#{ pluralize(unused, "license") } unused"
    end

    if billable_entity?
      "#{ pluralize(@consumed_licenses, "license") } used; #{ pluralize(@purchased_licenses, "license") } purchased; #{unused}"
    else
      "#{ pluralize(@purchased_licenses, "license") } purchased by the enterprise; #{ pluralize(@entity_licenses, "license") } used by this org; #{ pluralize(@other_entities_licenses, "license") } used by other orgs; #{unused}"
    end
  end
end
