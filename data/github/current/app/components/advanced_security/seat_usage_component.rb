# typed: strict
# frozen_string_literal: true

# Display details of the number of seats used and available for Advanced Security.
# Typically a meter is shown to indicate usage, but that's not shown in the unlimited case.
#
# This component also makes banner_* methods available to the enclosing template/component
# which can be used to determine whether a banner should be shown and what its message should be.
# Banners are not rendered directly in this component, since that approach offers less
# flexibility about layout.
class AdvancedSecurity::SeatUsageComponent < ApplicationComponent

  sig { returns(T::Boolean) }
  attr_reader :allowance_exceeded

  sig { returns(Integer) }
  attr_reader :entity_licenses

  sig { returns(Integer) }
  attr_reader :other_entities_licenses

  sig { returns(Integer) }
  attr_reader :purchased_licenses

  sig do
    params(
      sku: GitHub::Turboghas::SKU,
      size: Symbol,
      consumed_licenses: Integer,
      purchased_licenses: T.nilable(Integer),
      server_only_committers: T.nilable(Integer),
      additional_metered_licenses: T.nilable(Integer),
      entity_licenses: T.nilable(Integer),
      unlimited: T::Boolean,
    ).void
  end
  def initialize(
    sku: GitHub::Turboghas::SKU::Bundled,
    # The first arg is set by the caller in the render call ...
    size: :default,
    # ... the rest are populated by kwargs_for
    consumed_licenses: 0,
    purchased_licenses: 0,
    server_only_committers: nil,
    additional_metered_licenses: nil,
    # if this component is used for a business-owned org, this number is
    # how many that org is using as opposed to the full business total
    entity_licenses: nil,
    unlimited: false
  )
    @sku = sku
    @consumed_licenses = consumed_licenses
    # legacy licenses might have nil here; treat that as unlimited
    @purchased_licenses = T.let(purchased_licenses || 0, Integer)
    @additional_metered_licenses = additional_metered_licenses
    @server_only_committers = server_only_committers

    if entity_licenses.nil?
      @is_billable_entity = T.let(true, T::Boolean)
      @entity_licenses = T.let(consumed_licenses, Integer)
      @other_entities_licenses = T.let(0, Integer)
    else
      @is_billable_entity = T.let(false, T::Boolean)
      @entity_licenses = T.let(entity_licenses, Integer)
      @other_entities_licenses = T.let(consumed_licenses - entity_licenses, Integer)
    end

    @unlimited = unlimited
    @allowance_exceeded = T.let(!unlimited && (consumed_licenses > @purchased_licenses), T::Boolean)
    @at_allowance_limit = T.let(!unlimited && (consumed_licenses == @purchased_licenses) && @purchased_licenses > 0, T::Boolean)
    @size = size
  end

  sig { returns(Integer) }
  def server_only_committers
    @server_only_committers || 0
  end

  sig { returns(Integer) }
  def additional_metered_licenses
    @additional_metered_licenses || 0
  end

  sig { returns(T.any(String, Integer)) }
  def available_licenses
    return "unlimited" if @unlimited

    @purchased_licenses - @consumed_licenses
  end

  sig { returns(Integer) }
  def consumed_licenses_percent
    return 0 if purchased_licenses <= 0
    percent = (@consumed_licenses.to_f / purchased_licenses).round(2)
    (percent * 100).to_i
  end

  sig { returns(Integer) }
  def entity_licenses_percent
    return 0 if purchased_licenses <= 0
    percent = (@entity_licenses.to_f / purchased_licenses).round(2)
    (percent * 100).to_i
  end

  sig { returns(Integer) }
  def other_entities_licenses_percent
    return 0 if purchased_licenses <= 0
    percent = (@other_entities_licenses.to_f / purchased_licenses).round(2)
    (percent * 100).to_i
  end

  sig { returns(String) }
  memoize def sku_title
    case @sku
    when GitHub::Turboghas::SKU::Bundled
      "Secret Protection and Code Security"
    when GitHub::Turboghas::SKU::CodeSecurity
      "Code Security"
    when GitHub::Turboghas::SKU::SecretSecurity
      "Secret Protection"
    end
  end

  sig { returns(T::Boolean) }
  def bundled?
    @sku == GitHub::Turboghas::SKU::Bundled
  end

  # This component provides banner details which the enclosing template/component can use.
  # These aren't rendered directly in this component itself, since this prevents the banner
  # being rendered in a different location in the UI.
  sig { returns(T::Boolean) }
  def banner_required?
    @allowance_exceeded || @at_allowance_limit
  end

  sig { returns(T::Boolean) }
  def allowance_exceeded?
    @allowance_exceeded
  end

  sig { returns(String) }
  def banner_message
    return "" if @unlimited
    return "" if !@allowance_exceeded && !@at_allowance_limit

    prefix = @is_billable_entity ? "You are" : "Your enterprise is"
    suffix = if @allowance_exceeded
      "using #{ pluralize(number_with_delimiter(@consumed_licenses), "#{sku_title} license") }, " +
      "exceeding #{@is_billable_entity ? "your" : "the"} limit of #{number_with_delimiter(@purchased_licenses)}."
    else
      "at capacity for #{@is_billable_entity ? "your" : "its"} #{sku_title} license."
    end

    "#{prefix} #{suffix}"
  end

  sig { returns(T::Hash[Symbol, Symbol]) }
  def banner_arguments
    {
      icon: @allowance_exceeded ? :stop : :alert,
      scheme: @allowance_exceeded ? :danger : :warning,
    }
  end

  private

  sig { returns(T::Boolean) }
  def billable_entity?
    @is_billable_entity
  end

  sig { returns(String) }
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
      "#{ pluralize(@consumed_licenses, "#{sku_title} license") } used; #{ pluralize(@purchased_licenses, "license") } purchased; #{unused}"
    else
      "#{ pluralize(@purchased_licenses, "license") } purchased by the enterprise; #{ pluralize(@entity_licenses, "license") } used by this org; #{ pluralize(@other_entities_licenses, "license") } used by other orgs; #{unused}"
    end
  end
end
