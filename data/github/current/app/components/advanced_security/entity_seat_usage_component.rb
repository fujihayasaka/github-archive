# typed: strict
# frozen_string_literal: true

# Display details of the number of seats used and available for Advanced Security.
# Typically a meter is shown to indicate usage, but that's not shown in the unlimited case.
#
# This component also makes banner_* methods available to the enclosing template/component
# which can be used to determine whether a banner should be shown and what its message should be.
# Banners are not rendered directly in this component, since that approach offers less
# flexibility about layout.
class AdvancedSecurity::EntitySeatUsageComponent < ApplicationComponent
  sig do
    params(
      entity: T.any(User, Organization, Business),
      size: Symbol,
    ).void
  end
  def initialize(entity:, size: :default)
    @size = size
    @is_bundled = T.let(entity.advanced_security_license.billable_entity&.advanced_security_products_bundled? == true, T::Boolean)
    @entity = T.let(entity, T.nilable(T.any(User, Organization, Business)))
  end

  sig { returns(T::Boolean) }
  def is_bundled?
    @is_bundled
  end

  sig { params(path: Method, kwargs: T.untyped).returns(T.untyped) }
  def download_report_component(path:, **kwargs)
    return Primer::Box.new unless @entity.is_a?(Business) || @entity.is_a?(Organization)

    if is_bundled?
      Billing::DownloadReportComponent.new(**kwargs, tag: :a, href: path[@entity], test_selector: "secret-protection-and-code-security-report", aria: { label: "Download Advanced Security committers CSV report" })
    else
      Primer::Alpha::ActionMenu.new(size: :small, test_selector: "download-entity-usage-report").tap do |menu|
        menu.with_show_button(**kwargs) do |button|
          button.with_trailing_action_icon(icon: :"triangle-down")
          "Download report"
        end
        if @entity.secret_protection_purchased?
          menu.with_item(label: "Secret protection", test_selector: "secret-protection-report", href: path[@entity, sku: GitHub::Turboghas::SKU::SecretSecurity.to_param]) do |item|
            item.with_leading_visual_icon(icon: :download)
          end
        end
        if @entity.code_security_purchased?
          menu.with_item(label: "Code security", test_selector: "code-security-report", href: path[@entity, sku: GitHub::Turboghas::SKU::CodeSecurity.to_param]) do |item|
            item.with_leading_visual_icon(icon: :download)
          end
        end
      end
    end
  end

  sig { returns(T.nilable(T::Boolean)) }
  def render?
    @entity&.is_a?(Business) || @entity&.is_a?(Organization)
  end

  sig { returns(T::Array[AdvancedSecurity::SeatUsageComponent]) }
  memoize def components
    entity = T.cast(@entity, T.any(Organization, Business))

    license = entity.advanced_security_license
    code_security = entity.code_security
    secret_protection = entity.secret_protection

    if @is_bundled
      [
        AdvancedSecurity::SeatUsageComponent.new(
          sku: GitHub::Turboghas::SKU::Bundled,
          size: @size,
          consumed_licenses: license.consumed_seats,
          entity_licenses: (entity.advanced_security_seats_used(sku: GitHub::Turboghas::SKU::Bundled) unless entity.advanced_security_billable_entity?),
          purchased_licenses: license.seats,
          server_only_committers: license.ghes_committers&.all&.count,
          additional_metered_licenses: license.additional_metered_seats,
          unlimited: license.unlimited_seats?,
        )
      ]
    else
      [].tap do |components|
        if entity.secret_protection_purchased?
          components << AdvancedSecurity::SeatUsageComponent.new(
            sku: GitHub::Turboghas::SKU::SecretSecurity,
            size: @size,
            consumed_licenses: secret_protection.seats_used,
            entity_licenses: (entity.advanced_security_seats_used(sku: GitHub::Turboghas::SKU::SecretSecurity) unless entity.advanced_security_billable_entity?),
            purchased_licenses: secret_protection.seats,
            server_only_committers: secret_protection.ghes_committers&.all&.count,
            additional_metered_licenses: secret_protection.additional_metered_committers_used,
            unlimited: secret_protection.unlimited_seats?,
          )
        end
        if entity.code_security_purchased?
          components << AdvancedSecurity::SeatUsageComponent.new(
            sku: GitHub::Turboghas::SKU::CodeSecurity,
            size: @size,
            consumed_licenses: code_security.seats_used,
            entity_licenses: (entity.advanced_security_seats_used(sku: GitHub::Turboghas::SKU::CodeSecurity) unless entity.advanced_security_billable_entity?),
            purchased_licenses: code_security.seats,
            server_only_committers: code_security.ghes_committers&.all&.count,
            additional_metered_licenses: code_security.additional_metered_committers_used,
            unlimited: code_security.unlimited_seats?,
          )
        end
      end
    end
  end

  # This component provides banner details which the enclosing template/component can use.
  # These aren't rendered directly in this component itself, since this prevents the banner
  # being rendered in a different location in the UI.

  sig { returns(T::Boolean) }
  def banner_required?
    components.any?(&:banner_required?)
  end

  sig { returns(T::Hash[Symbol, Symbol]) }
  def banner_arguments
    component = components.find(&:allowance_exceeded?) || components.find(&:banner_required?)
    component ? component.banner_arguments : {}
  end

  sig { returns(String) }
  def banner_message
    components.any?(&:banner_required?) ? components.map(&:banner_message).join(" ") : ""
  end
end
