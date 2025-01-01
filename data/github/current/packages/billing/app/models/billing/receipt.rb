# typed: strict
# frozen_string_literal: true

module Billing
  class Receipt
    include ActionView::Helpers::TextHelper
    include ActionView::Helpers::NumberHelper
    include GitHub::Memoizer

    sig { returns(Billing::BillingTransaction) }
    attr_reader :billing_transaction

    delegate :amount,
             :asset_packs_delta,
             :asset_packs_total,
             :card_number,
             :card_type,
             :created_at,
             :credit_balance_adjustment_transaction?,
             :discount_in_cents,
             :line_items,
             :paypal_email,
             :plan_name,
             :prorated_days,
             :old_plan_name,
             :seats_delta,
             :seats_total,
             :transaction_type,
             :billable_entity,
             :yearly?,
             :job_posting?,
             :is_refund?,
             :last_four,
             :transaction_id,
             :sale_transaction_id,
             :tax_amount,
      to: :billing_transaction

    # Public: Create a Receipt for subscription payment.
    sig do
      params(
        billing_transaction: Billing::BillingTransaction,
        viewer: T.nilable(User)
      ).void
    end
    def initialize(billing_transaction, viewer: nil)
      @billing_transaction = billing_transaction
      @viewer = viewer
    end

    # Public: String standarized filename based on the login of the user and
    # date of transaction.
    sig { returns(String) }
    def pdf_filename
      "github-#{billable_entity}-receipt-#{purchased_at.strftime("%Y-%m-%d")}.pdf"
    end

    # Public: Returns a PDF rendering of this receipt.
    #
    # show_email_address - Boolean if billing email address should be included
    #                      on the receipt.
    sig { params(show_email_address: T::Boolean).returns(String) }
    def to_pdf(show_email_address: true)
      PdfRenderer.new(
        self,
        show_email_address: show_email_address,
        viewer: viewer
      ).render
    end

    sig { returns(T.nilable(T::Boolean)) }
    def display_github_plan?
      plan = self.plan
      plan && !plan.free? && !plan.free_with_addons?
    end

    sig { returns(T::Boolean) }
    def display_tax?
      return false if billing_transaction.tax_items.empty?

      billable_entity&.feature_enabled?(:tax_line_items) || GitHub.flipper[:tax_line_items].enabled?
    end

    sig { returns(T::Boolean) }
    def display_payment_identifier?
      !credit_balance_adjustment_transaction?
    end

    sig { returns(T.nilable(T::Boolean)) }
    def display_service_through?
      !is_refund? && (
        display_github_plan? ||
        plan_renewal_with_data_packs? ||
        actions_line_items_displayable? ||
        package_registry_transfer_line_items_displayable? ||
        shared_storage_line_items_displayable? ||
        codespaces_line_items_displayable? ||
        marketplace_line_items_displayable? ||
        show_metered_copilot_row? ||
        advanced_security_line_items_displayable? ||
        sponsorship_line_items_displayable?
      )
    end

    sig { returns(String) }
    def receipt_header
      text = []
      text << "GITHUB RECEIPT -"
      text << (account_type_for_header)
      text << (prorated_charge? ? "PURCHASE" : "SUBSCRIPTION")
      text << "-"
      text << billable_entity.to_s
      text.join(" ")
    end

    # Public: String plan summary of items purchased.
    sig { returns(T.nilable(String)) }
    def plan_summary
      case transaction_type
      when "prorate-charge"
        added_seats_text || prorated_yearly_upgrade_text
      when "prorate-seat-charge"
        added_seats_text
      when "prorate-asset-pack-charge"
        added_data_packs_text
      when "prorate-switch-to-seat-charge"
        "Switch to #{plan_display_name} (#{pluralize(seats_total, "seat")})"
      when "job-posting"
        "Job posting"
      when "job-credits"
        "Job posting credits"
      else
        if per_seat?
          switch_to_per_seat_text || per_seat_renewal_text
        else
          repository_plan_text
        end
      end
    end

    sig { returns(T.nilable(T::Boolean)) }
    def per_seat?
      plan&.per_seat?
    end

    sig { returns(T::Boolean) }
    def added_seats?
      per_seat? && seats_delta > 0
    end

    # Internal: Boolean if billing_transaction records a switch to per seat pricing.
    sig { returns(T.nilable(T::Boolean)) }
    def switched_to_per_seat?
      old_plan = self.old_plan
      per_seat? && (transaction_type == "prorate-switch-to-seat-charge" || (old_plan && !old_plan.per_seat?))
    end

    # Public: The amount tied to a GitHub plan, e.g. plan price and data packs
    sig { returns(Billing::Money) }
    memoize def plan_amount
      Billing::Money.new([amount - usage_amount - marketplace_amount - sponsorship_amount_including_fees -
        copilot_amount - advanced_security_amount, 0].max)
    end

    sig { returns(String) }
    def payment_type
      paypal_email ? "PayPal account" : card_type
    end

    sig { returns(String) }
    def payment_identifier
      paypal_email.presence || card_number
    end

    sig { returns(ActiveSupport::TimeWithZone) }
    def purchased_at
      created_at.in_billing_timezone
    end

    sig { returns(String) }
    def service_ends_on
      service_ends_at.in_billing_timezone.strftime("%Y-%m-%d")
    end

    sig { returns(T.nilable(String)) }
    def vat_code
      billable_entity&.vat_code
    end

    sig { returns(T.nilable(String)) }
    def extra
      billable_entity&.billing_extra
    end

    sig { returns(T::Boolean) }
    def prorated_charge?
      transaction_type.match?(/prorate/)
    end

    sig { returns(T.nilable(String)) }
    def data_packs_addon_text
      if plan_renewal_with_data_packs?
        "#{pluralize(asset_packs_total, "data pack")} (#{data_pack_cost_text})"
      end
    end

    sig { returns(T::Boolean) }
    def plan_renewal_with_data_packs?
      !prorated_charge? && asset_packs_delta == 0 && asset_packs_total > 0
    end

    # Public: Select only line items tied to marketplace purchases
    sig { returns(ActiveRecord::AssociationRelation) }
    memoize def marketplace_line_items
      line_items.marketplace
    end

    # Public: Whether we should display the marketplace line items section
    sig { returns(T::Boolean) }
    memoize def marketplace_line_items_displayable?
      marketplace_line_items.any?
    end

    # Public: Select only line items tied to sponsorships. Includes both fee and non-fee line items.
    sig { returns(ActiveRecord::AssociationRelation) }
    memoize def sponsorship_line_items
      line_items.sponsorships.order(:id).preload(subscribable: :sponsors_listing)
    end

    # Public: Select only line items tied to sponsorships that represent a service fee paid to GitHub, as opposed
    # to the amount paid out to the maintainer being sponsored.
    sig { returns(T::Array[Billing::BillingTransaction::LineItem]) }
    memoize def fee_sponsorship_line_items
      sponsorship_line_items.select(&:sponsors_fee?)
    end

    # Public: Select only line items tied to sponsorships that do not represent a service fee paid to GitHub,
    # but rather an amount paid out to the maintainer being sponsored.
    sig { returns(T::Array[Billing::BillingTransaction::LineItem]) }
    memoize def non_fee_sponsorship_line_items
      sponsorship_line_items - fee_sponsorship_line_items
    end

    # Public: Select only line items tied to advanced security
    sig { returns(ActiveRecord::AssociationRelation) }
    memoize def advanced_security_line_items
      line_items.advanced_security
    end

    # Public: Select only line items tied to copilot for individuals
    sig { returns(ActiveRecord::AssociationRelation) }
    memoize def copilot_line_items
      line_items.copilot
    end

    # Public: Select only line items tied to metered copilot
    sig { returns(ActiveRecord::AssociationRelation) }
    memoize def metered_copilot_line_items
      line_items.metered_copilot_usage
    end

    # Public: Select only line items tied to Copilot for Business
    sig { returns(ActiveRecord::AssociationRelation) }
    memoize def copilot_for_business_line_items
      line_items.copilot_for_business_usage
    end

    # Public: Select only line items tied to Actions private usage
    sig { returns(ActiveRecord::AssociationRelation) }
    memoize def actions_line_items
      line_items.actions_usage
    end

    # Public: Whether we should display the actions line items section
    sig { returns(T::Boolean) }
    memoize def actions_line_items_displayable?
      filter_zero_value_line_items(line_items.actions_usage).any?
    end

    # Public: Select only line items tied to Package Registry Data Usage
    sig { returns(ActiveRecord::AssociationRelation) }
    memoize def package_registry_transfer_line_items
      line_items.packages_data_transfer_usage
    end

    # Public: Whether we should display the package data transfer line items section
    sig { returns(T::Boolean) }
    memoize def package_registry_transfer_line_items_displayable?
      filter_zero_value_line_items(line_items.packages_data_transfer_usage).any?
    end

    # Public: Select only line items tied to Share Storage Usage
    sig { returns(ActiveRecord::AssociationRelation) }
    memoize def shared_storage_line_items
      line_items.shared_storage_usage
    end

    # Public: Whether we should display the shared storage line items section
    sig { returns(T::Boolean) }
    memoize def shared_storage_line_items_displayable?
      filter_zero_value_line_items(line_items.shared_storage_usage).any?
    end

    # Public: Select only line items tied to Codespaces Storage Usage
    sig { returns(ActiveRecord::AssociationRelation) }
    memoize def codespaces_storage_line_items
      line_items.codespaces_storage_usage
    end

    # Public: Select only line items tied to Codespaces Compute Usage
    sig { returns(ActiveRecord::AssociationRelation) }
    memoize def codespaces_compute_line_items
      line_items.codespaces_compute_usage
    end

    # Public: Select only line items tied to Codespaces - Compute or Storage
    sig { returns(ActiveRecord::AssociationRelation) }
    memoize def codespaces_line_items
      line_items.codespaces_usage
    end

    # Public: Format marketplace line items for display
    sig { returns(String) }
    def marketplace_line_items_text
      marketplace_line_items.map do |item|
        "#{item.subscribable.listing.name} - #{item.subscribable_name}"
      end.join("\n")
    end

    # Public: Format sponsorship line items for display
    sig { returns(String) }
    def sponsorship_line_items_text
      sponsorship_line_items.map(&:receipt_text).join("\n")
    end

    # Public: Format Actions usage line items for display
    sig { returns(T.nilable(String)) }
    def actions_line_items_text
      if actions_line_items.length == 1
        action_line_items_included_only_text
      elsif actions_line_items.length > 1
        actions_line_items_with_overages_text
      end
    end

    # Public: Format Packages usage line items for display
    sig { returns(T.nilable(String)) }
    def packages_transfer_line_items_text
      if package_registry_transfer_line_items.length == 1
        packages_transfer_line_items_included_only_text
      elsif package_registry_transfer_line_items.length > 1
        packages_transfer_line_items_with_overages_text
      end
    end

    # Public: Format Shared Storage line items for display
    sig { returns(T.nilable(String)) }
    def shared_storage_line_items_text
      if shared_storage_line_items.length == 1
        shared_storage_line_items_included_only_text
      elsif shared_storage_line_items.length > 1
        shared_storage_line_items_with_overages_text
      end
    end

    # Public: Sums the amount for codespaces line items
    sig { returns(Billing::Money) }
    memoize def codespaces_amount
      Billing::Money.new(codespaces_line_items.sum(:amount_in_cents))
    end

    # Public: Sums the amount for marketplace line items
    sig { returns(Billing::Money) }
    memoize def marketplace_amount
      Billing::Money.new marketplace_line_items.sum(:amount_in_cents)
    end

    # Public: Sums the amount for sponsorship line items, excluding fees.
    sig { returns(Billing::Money) }
    memoize def sponsorship_amount_excluding_fees
      Billing::Money.new(non_fee_sponsorship_line_items.sum(&:amount_in_cents))
    end

    # Public: Sums the amount for sponsorship line items, including fees.
    sig { returns(Billing::Money) }
    memoize def sponsorship_amount_including_fees
      sponsorship_amount_excluding_fees + sponsorship_fees_amount
    end

    # Public: Sums the amount for sponsorship fee line items.
    sig { returns(Billing::Money) }
    memoize def sponsorship_fees_amount
      Billing::Money.new(fee_sponsorship_line_items.sum(&:amount_in_cents))
    end

    # Public: Sums the amount for advanced security line items
    sig { returns(Billing::Money) }
    def advanced_security_amount
      Billing::Money.new(advanced_security_line_items.sum(:amount_in_cents))
    end

    # Public: Sums the amount for copilot for individuals line items
    sig { returns(Billing::Money) }
    memoize def copilot_amount
      Billing::Money.new(copilot_line_items.sum(:amount_in_cents))
    end

    # Public: Sums the amount for metered copilot line items
    sig { returns(Billing::Money) }
    memoize def metered_copilot_amount
      Billing::Money.new(metered_copilot_line_items.sum(:amount_in_cents))
    end

    # Public: Sums the amount for line items associated with usage products
    sig { returns(Billing::Money) }
    def usage_amount
      actions_amount + package_registry_transfer_amount + shared_storage_amount + codespaces_amount +
        metered_copilot_amount
    end

    # Public: Sums the amount for Actions line items
    sig { returns(Billing::Money) }
    memoize def actions_amount
      Billing::Money.new actions_line_items.sum(:amount_in_cents)
    end

    # Public: Sums the amount for Copilot for business line items
    sig { returns(Billing::Money) }
    def copilot_for_business_amount
      Billing::Money.new copilot_for_business_line_items.sum(:amount_in_cents)
    end

    # Public: Sums the amount for Package Registry transfer line items
    sig { returns(Billing::Money) }
    def package_registry_transfer_amount
      Billing::Money.new package_registry_transfer_line_items.sum(:amount_in_cents)
    end

    # Public: Sums the amount for GitHub Shared Storage line items
    sig { returns(Billing::Money) }
    def shared_storage_amount
      Billing::Money.new shared_storage_line_items.sum(:amount_in_cents)
    end

    # Public: Whether we should display the sponsorship line items section
    sig { returns(T::Boolean) }
    memoize def sponsorship_line_items_displayable?
      sponsorship_line_items.any?
    end

    # Public: Whether we should display the advanced security line items section
    sig { returns(T::Boolean) }
    memoize def advanced_security_line_items_displayable?
      advanced_security_line_items.any?
    end

    # Public: Include the proration message if necessary
    sig { returns(T.nilable(String)) }
    def advanced_security_formatted_amount
      line_item = advanced_security_line_items.first
      return unless line_item

      quantity = advanced_security_quantity
      proration_message = advanced_security_prorated_message
      price = line_item.subscribable.base_price.to_i

      # Return "1 seat ($49/month each)" if there is no proration
      return "#{pluralize(quantity, "seat")} ($#{price}/" + advanced_security_subscription_term + " each)" if proration_message.empty?
      # Return "1 seat ($49/month - prorated for x days) if the charge is prorated
      "#{pluralize(quantity, "seat")} ($#{price}/" + advanced_security_subscription_term + " each" + proration_message
    end

    # Public: Whether we should display the copilot line items section
    sig { returns(T::Boolean) }
    memoize def copilot_line_items_displayable?
      copilot_line_items.any?
    end

    sig { returns(T.nilable(Billing::BillingTransaction::LineItem)) }
    memoize def copilot_line_item
      copilot_line_items.max_by(&:amount_in_cents)
    end

    sig { returns(String) }
    def copilot_formatted_amount
      proration_message = copilot_prorated_message
      amount = copilot_amount.format(with_currency: false)

      # Return "$10/month" if there is no proration
      return amount + "/" + copilot_subscription_term if proration_message.empty?
      # Return "$5.60 ($10/month - prorated for x days) if the charge is prorated
      amount + proration_message
    end

    # Public: Returns the proration message for a copilot line item if it exists
    sig { returns(String) }
    def copilot_prorated_message
      line_item = copilot_line_item
      return "" unless line_item
      return "" if created_at.blank? || service_ends_at.blank?
      return "" unless prorated_days_with_fallback.positive?
      price = line_item.subscribable.base_price.to_i
      # Some billing transactions are incorrectly marked as prorated when they are not. As a workaround,
      # only show the prorated message if the price charged is different from the base price.
      return "" if price == copilot_amount.to_i

      " ($#{price}/#{copilot_subscription_term} - prorated for #{pluralize(prorated_days_with_fallback, "day")})"
    end

    # Public: Returns the proration message for an advanced security line item if it exists
    sig { returns(String) }
    def advanced_security_prorated_message
      return "" if created_at.blank? || service_ends_at.blank?
      return "" unless prorated_days_with_fallback.positive?

      " - prorated for #{pluralize(prorated_days_with_fallback, "day")})"
    end

    # Public: Returns the quantity for an advanced security line item if it exists
    sig { returns(String) }
    def advanced_security_quantity
      line_item = advanced_security_line_items.first
      return "" unless line_item

      strip_insignificant_zeros(line_item.quantity, precision: 4)
    end

    # Public: Defines the Advanced Security subscription term
    sig { returns(String) }
    def advanced_security_subscription_term
      line_item = advanced_security_line_items.first
      return "" unless line_item
      line_item.subscribable.billing_cycle
    end

    # Public: Defines the Copilot subscription term
    sig { returns(String) }
    def copilot_subscription_term
      line_item = copilot_line_item
      return "" unless line_item
      line_item.subscribable.billing_cycle
    end

    sig do
      params(line_items: T::Enumerable[Billing::BillingTransaction::LineItem])
      .returns(T::Array[Billing::BillingTransaction::LineItem])
    end
    def filter_zero_value_line_items(line_items)
      unless billable_entity&.feature_enabled?(:filter_zero_value_line_items) || GitHub.flipper[:filter_zero_value_line_items].enabled?
        return line_items.to_a
      end

      # We generate a lot of "empty" line items due to the way Zuora subscriptions work, so we filter them out here.
      if generic_line_item_feature_enabled_for_billable_entity? || generic_line_item_feature_enabled_for_viewer?
        # Viewer will be nil when emailing, so only billable entity will be checked in that case
        line_items.reject { |item| item if item.amount_in_cents.zero? }
      else
        line_items.reject { |item| item if item.quantity.zero? && item.amount_in_cents.zero? }
      end
    end

    sig { returns(String) }
    def metered_copilot_text
      sku_to_line_items = metered_copilot_line_items.group_by(&:copilot_sku_description)
      sku_to_line_items = sku_to_line_items.sort.to_h

      text = []
      total_quantity = T.let(0, T.any(BigDecimal, Integer))

      sku_to_line_items.each do |sku, line_items|
        next if line_items.all? { |item| item.quantity.zero? }

        billed_in_full_count = 0
        prorations = Hash.new(0)
        unit_price = line_items.first&.extras&.fetch("unit_price", nil)
        unit_price ||= copilot_sku_price(line_items.first&.description)
        unit_price = unit_price.to_i if unit_price.is_a?(String)
        unit_price = unit_price.round
        sku_quantity = T.let(0, T.any(BigDecimal, Integer))
        text << "#{sku}:"

        line_items.each do |item|
          sku_quantity += item.quantity
          total_quantity += item.quantity

          next if item.extras.blank?

          billed_in_full_count += item.extras["seats_billed_in_full"].to_i
          if (proration_data = item.extras["prorations"].presence)
            proration_data.to_a.each do |item_proration|
              prorations[item_proration["days"]] += item_proration["count"].to_i
            end
          end
        end

        if billed_in_full_count.positive?
          text << "#{billed_in_full_count} #{("seat").pluralize(billed_in_full_count)} ($#{unit_price}/month each)"
        end

        prorations.sort.reverse_each do |days, count|
          text << "#{count} #{("seat").pluralize(count)} ($#{unit_price}/month each - prorated for #{days} #{("day").pluralize(days)})"
        end

        text << "#{strip_insignificant_zeros(sku_quantity, precision: 4)} billed #{("seat").pluralize(sku_quantity)} ($#{unit_price}/month each)"

        text << "" unless text.last.blank?
      end

      text << "#{strip_insignificant_zeros(total_quantity, precision: 4)} #{("total billed seat").pluralize(total_quantity)}"
      text.join("\n")
    end

    # Public: Returns the price if something goes wrong with grabbing unit price from extras
    sig { params(sku: T.nilable(String)).returns(T.nilable(BigDecimal)) }
    def copilot_sku_price(sku)
      if sku == "GitHub Copilot"
        Billing::ProductUUID.copilot.with_product_key("business.v0").last&.base_price&.dollars
      else
        Billing::ProductUUID.copilot.with_product_key(sku).last&.base_price&.dollars
      end
    end

    # Public: Whether the receipt is a result of adding/updating
    # a sponsorship mid-cycle.
    sig { returns(T::Boolean) }
    def sponsorship_only_transaction?
      [plan_amount, actions_amount, marketplace_amount].all?(&:zero?) && !sponsorship_amount_including_fees.zero?
    end

    sig { returns(String) }
    def sponsorship_only_text
      total_sponsorships = non_fee_sponsorship_line_items.count
      "We received payment for your #{'sponsorship'.pluralize(total_sponsorships)}. " \
        "Thanks for your support of Open Source Software!"
    end

    sig { returns(String) }
    def sponsorship_prorated_message
      return "" unless prorated_charge?
      return "" if created_at.blank?
      return "" if service_ends_at.blank?
      return "" if sponsorship_line_items.all?(&:one_time?)

      proration_start = created_at.strftime("%b %e")
      proration_end = service_ends_at.strftime("%b %e")

      " (prorated for #{proration_start} - #{proration_end})"
    end

    # Public: Description of codespaces compute and storage usage.
    # When plan does not exist, it will fail gracefully and generate
    # a Failbot report and return description.
    sig { returns(String) }
    def codespaces_line_items_text
      unless plan
        Failbot.report(
          RuntimeError.new("Missing plan_name in billing transaction with codespaces usage"),
          { "gh.billing.transaction.id" => billing_transaction.id },
        )
      end

      compute_text = codespaces_line_item_text(
        items: codespaces_compute_line_items,
        type: "compute",
        unit: "hour"
      )

      storage_text = codespaces_line_item_text(
        items: codespaces_storage_line_items,
        type: "storage",
        unit: "GB"
      )

      [codespaces_entitlements_included_text, compute_text, storage_text].reject(&:empty?).join("\n")
    end

    sig { returns(T::Boolean) }
    memoize def eligible_for_codespaces_entitlements?
      ::Codespaces::Policy.entitlements_feature_enabled?(billing_transaction.user)
    end

    sig { returns(T::Array[String]) }
    memoize def codespaces_entitlements_included_text
      plan = self.plan
      # Show included usage total if user has included usage in their plan for this period.
      # We don't know how much included usage they have used, so we can't show the consumed entitlements
      # (technical limitation). Instead we list the total included usage and their overages, if any.
      # Users can see details on their consumed usage in the Billing UI.
      if eligible_for_codespaces_entitlements? && plan.present?
        included_storage = plan.codespaces_included_storage_gigabyte_months.to_i
        included_compute = plan.codespaces_included_compute_hours.to_i
        return [
          "#{included_compute} #{"core-hour".pluralize(included_compute.to_i)} included",
          "#{included_storage}GB of storage included",
        ]
      end

      []
    rescue GitHub::Plan::EntitlementError
      []
    end

    # Public: Whether we should display the codespaces line items section
    sig { returns(T::Boolean) }
    def codespaces_line_items_displayable?
      codespaces_amount > 0
    end

    sig { returns(String) }
    def annual_discount_text
      "#{annual_discount_percentage.round(2)}%"
    end

    sig { returns(Billing::Money) }
    def annual_discount_amount
      # It is possible that additional_seats is 0 while seats_delta is positive
      # And vice-versa, so we need to check all of them.
      new_seats = [seats_delta, seats_total].max
      undiscounted_value = Billing::Money.new(plan_unit_cost) * new_seats
      undiscounted_value - plan_amount
    end

    sig { returns(Billing::Types::NonMoneyNumeric) }
    def annual_discount_percentage
      plan = self.plan
      return 0 unless plan

      plan.yearly_discount_percentage
    end

    sig { returns(T.nilable(T::Boolean)) }
    def has_annual_discount?
      return false if billable_entity.is_a?(Billing::DeadUser) || billable_entity.nil?

      yearly? && billable_entity.annual_discount_allowed? && annual_discount_amount > 0
    end

    sig { returns(T.nilable(String)) }
    def charged_to_text
      return if credit_balance_adjustment_transaction?
      "Charged to: #{payment_type} (#{payment_identifier})"
    end

    # We only show the Copilot for Business row on a receipt if the user has CFB enabled. We also show it for
    # deactivated users because the CFB enabled check isn't defined for `DeadUsers`.
    sig { returns(T::Boolean) }
    def show_metered_copilot_row?
      return false unless billable_entity.is_a?(Billing::DeadUser) || (
        !billable_entity.nil? &&
        ::Copilot.copilot_object(billable_entity).copilot_for_business_enabled?
      )
      metered_copilot_amount > 0
    end

    sig { returns(T::Boolean) }
    def show_actions_row?
      actions_amount > 0
    end

    sig { returns(T::Boolean) }
    def show_packages_row?
      package_registry_transfer_amount > 0
    end

    sig { returns(T::Boolean) }
    def show_shared_storage_row?
      shared_storage_amount > 0
    end

    # Public: Returns line items not associated with marketplace or sponsorship.
    sig { returns(T::Array[Billing::BillingTransaction::LineItem]) }
    memoize def generic_line_items
      # Sponsors/marketplace line items have special formatting, so we exclude them from the generic line items.
      filtered_items = filter_zero_value_line_items(line_items - marketplace_line_items - sponsorship_line_items)
      group_github_team_line_items(line_items: filtered_items)
    end

    # Public: Whether or not there are any generic line items to display.
    sig { returns(T::Boolean) }
    memoize def generic_line_items_displayable?
      generic_line_items.any?
    end

    # Public: Returns generically formated text entries for all non-zero generic line items.
    sig { returns(String) }
    def generic_line_items_text
      generic_line_items.map do |item|
        # For billing-platform charges, we can only show the description and the amount
        # because the quantity is not a measure of units, it's the actual cost.
        period_text = item.formatted_service_period(format: "%b %-d, %Y", separator: "-")
        "#{item.description}: #{item.to_money.format(with_currency: true)}\n#{period_text}"
      end.join("\n\n")
    end

    # Public: Whether the generic line item feature is enabled for the current viewer.
    sig { returns(T::Boolean) }
    def generic_line_item_feature_enabled_for_viewer?
      return false unless created_at >= LINE_ITEM_PRODUCT_RATE_PLAN_CHARGE_IDS_EFFECTIVE_DATE
      self.viewer&.feature_enabled?(:payment_receipt_line_item_format) || GitHub.flipper[:payment_receipt_line_item_format].enabled?
    end

    # Public: Whether the generic line item feature is enabled for the receipt's billable entity.
    sig { returns(T::Boolean) }
    def generic_line_item_feature_enabled_for_billable_entity?
      return false unless created_at >= LINE_ITEM_PRODUCT_RATE_PLAN_CHARGE_IDS_EFFECTIVE_DATE
      billable_entity&.feature_enabled?(:payment_receipt_line_item_format) || GitHub.flipper[:payment_receipt_line_item_format].enabled?
    end

    private

    # Date when product rate plan charge IDs were applied to all line items: https://github.com/github/github/pull/330617
    # Product rate plan charge ID is used when building the line items for the billing_transaction itself
    LINE_ITEM_PRODUCT_RATE_PLAN_CHARGE_IDS_EFFECTIVE_DATE = T.let(Date.parse("2024-07-01"), Date)

    sig { returns(T.nilable(User)) }
    attr_reader :viewer

    sig { returns(String) }
    def account_type_for_header
      if billable_entity.is_a?(Business)
        "ENTERPRISE"
      elsif billable_entity.organization?
        "ORGANIZATION"
      else
        "PERSONAL"
      end
    end

    # Private: Aggregates the extra "GitHub Team - Month" and "GitHub Team - Annual" line items into individual
    # "- Month" and "- Annual" line items.
    # This is necessary because the GitHub Team Plan product in Zuora has two rate plans each for monthly and annual
    # and create two separate line items for each.
    # This is a quick-fix for this issue: https://github.com/github/gitcoin/issues/16337
    sig do
      params(line_items: T::Array[Billing::BillingTransaction::LineItem])
        .returns(T::Array[Billing::BillingTransaction::LineItem])
    end
    def group_github_team_line_items(line_items: [])

      # These come from the GitHub Team Plan product in Zuora
      # https://www.zuora.com/apps/Product.do?method=view&id=2c92a0ff60c505db0160d75cce4633f0
      github_team_annual_rate_plan_charge_ids = GitHub::Plan.business.product_uuid(Business::BillingDependency::YEARLY_PLAN)&.zuora_product_rate_plan_charge_ids
      github_team_monthly_rate_plan_charge_ids = GitHub::Plan.business.product_uuid(Business::BillingDependency::MONTHLY_PLAN)&.zuora_product_rate_plan_charge_ids

      annual_units_rate_plan_charge_ids = T.let([], T::Array[String])
      monthly_units_rate_plan_charge_ids = T.let([], T::Array[String])

      if !github_team_annual_rate_plan_charge_ids.nil?
        annual_units_rate_plan_charge_ids = [github_team_annual_rate_plan_charge_ids[:unit], github_team_annual_rate_plan_charge_ids[:base_unit]]
      end

      if !github_team_monthly_rate_plan_charge_ids.nil?
        monthly_units_rate_plan_charge_ids = [github_team_monthly_rate_plan_charge_ids[:unit], github_team_monthly_rate_plan_charge_ids[:base_unit]]
      end

      github_team_annual_line_items = T.let([], T::Array[Billing::BillingTransaction::LineItem])
      github_team_monthly_line_items = T.let([], T::Array[Billing::BillingTransaction::LineItem])

      line_items.each do |item|
        if annual_units_rate_plan_charge_ids.include?(item.zuora_product_rate_plan_charge_id)
          github_team_annual_line_items << item
        elsif monthly_units_rate_plan_charge_ids.include?(item.zuora_product_rate_plan_charge_id)
          github_team_monthly_line_items << item
        end
      end

      combined_line_items = [github_team_annual_line_items, github_team_monthly_line_items].filter_map do |items|
        if item = items.first
          # Only adding the fields that make sense to combine, if new fields are added to line items,
          # they may need to be added here as well at that time.
          Billing::BillingTransaction::LineItem.new(
            description: item.description,
            amount_in_cents: items.sum(&:amount_in_cents),
            quantity: items.sum(&:quantity),
            service_start_date: item.service_start_date,
            service_end_date: item.service_end_date,
          )
        end
      end

      non_github_team_line_items = line_items - github_team_annual_line_items - github_team_monthly_line_items
      combined_line_items + non_github_team_line_items
    end

    # Private: Description for included and paid given codespaces usage
    sig { params(items: T::Enumerable[Billing::BillingTransaction::LineItem], type: String, unit: String).returns(String) }
    def codespaces_line_item_text(items:, type:, unit:)
      has_overages = has_codespace_entitlements_overages?

      items.sort_by(&:amount_in_cents).map do |item|
        next if item.amount_in_cents == 0
        quantity = strip_insignificant_zeros(item.quantity)
        core_count = item.core_count_from_description ? "(#{item.core_count_from_description})" : nil

        if unit == "hour"
          # Example: "220 hours of compute (2 core)" or "220 additional hours of compute (2 core)"
          next "#{quantity}#{has_overages ? " additional" : ""} #{unit.pluralize(quantity.to_i)} of #{type} #{core_count}".strip
        end

        # Example: "25GB of storage" or "25GB of additional storage"
        "#{quantity}#{unit} of #{has_overages ? "additional " : ""}#{type}"
      end.compact.join("\n")
    end

    sig { returns(T::Boolean) }
    memoize def has_codespace_entitlements_overages?
      return false unless eligible_for_codespaces_entitlements?
      codespaces_usage.has_entitlements_overages?
    end

    sig { returns(Billing::CodespacesUsage) }
    memoize def codespaces_usage
      Billing::CodespacesUsage.new(
        account: billing_transaction.user,
      )
    end

    # Private: Description of actions minutes when all minutes are included.
    # When plan does not exist, it will fail gracefully and generate
    # a Failbot report and return description minutes consumed without the total included.
    sig { returns(String) }
    def action_line_items_included_only_text
      unless plan
        Failbot.report(
          RuntimeError.new("Missing plan_name in billing transaction with actions usage"),
          { "gh.billing.transaction.id" => billing_transaction.id },
        )

        return actions_line_items_with_overages_text
      end

      item = actions_line_items.first
      return "" unless item

      "#{strip_insignificant_zeros(item.quantity)} of #{plan_actions_included_minutes} included private minutes #{item.to_money.format(with_currency: true)}"
    end

    sig { returns(Integer) }
    def plan_actions_included_minutes
      plan&.actions_included_private_minutes.to_i
    end

    # Private: Description of shared storage when all cost is included.
    # When plan does not exist, it will fail gracefully and generate
    # a Failbot report and return description with total included.
    sig { returns(String) }
    def shared_storage_line_items_included_only_text
      unless plan
        Failbot.report(
          RuntimeError.new("Missing plan_name in billing transaction with shared storage usage"),
          { "gh.billing.transaction.id" => billing_transaction.id },
        )

        return shared_storage_line_items_with_overages_text
      end

      item = shared_storage_line_items.first
      return "" unless item

      gigabytes = gigabytes_used(item.quantity)
      "#{gigabytes}GB of #{plan_shared_storage_included_gigabytes}GB included storage #{item.to_money.format(with_currency: true)}"
    end

    # Private: Description of shared storage when there are overages.
    sig { returns(String) }
    def shared_storage_line_items_with_overages_text
      filter_zero_value_line_items(shared_storage_line_items).map do |item|
        data_type = item.amount_in_cents == 0 ? "included" : "additional"

        gigabytes = gigabytes_used(item.quantity)
        "#{gigabytes}GB #{data_type} storage #{item.to_money.format(with_currency: true)}"
      end.join("\n")
    end

    # Private: Description of package data transfer when all cost is included.
    # When plan does not exist, it will fail gracefully and generate
    # a Failbot report and return description with total included.
    sig { returns(String) }
    def packages_transfer_line_items_included_only_text
      unless plan = self.plan
        Failbot.report(
          RuntimeError.new("Missing plan_name in billing transaction with package registry transfer usage"),
          { "gh.billing.transaction.id" => billing_transaction.id },
        )

        return packages_transfer_line_items_with_overages_text
      end

      item = package_registry_transfer_line_items.first
      return "" unless item

      "#{strip_insignificant_zeros(item.quantity)}GB of #{plan.package_registry_included_bandwidth}GB included data transfer out #{item.to_money.format(with_currency: true)}"
    end

    # Private: Description of data transfer charges when there are overages.
    sig { returns(String) }
    def packages_transfer_line_items_with_overages_text
      filter_zero_value_line_items(package_registry_transfer_line_items).map do |item|
        data_type = item.amount_in_cents == 0 ? "included" : "additional"
        "#{strip_insignificant_zeros(item.quantity)}GB #{data_type} data transfer out #{item.to_money.format(with_currency: true)}"
      end.join("\n")
    end

    # Private: Description of actions charges when there are overages.
    sig { returns(String) }
    def actions_line_items_with_overages_text
      filter_zero_value_line_items(actions_line_items).map do |item|
        minutes_type = item.amount_in_cents == 0 ? "included" : "additional"
        core_count = item.core_count_from_description ? "(#{item.core_count_from_description})" : nil

        next if core_count && item.amount_in_cents == 0

        text = "#{strip_insignificant_zeros(item.quantity)} #{minutes_type}"
        if core_count
          text << " #{("minute").pluralize(item.quantity)} #{core_count}"
        else
          text << " private #{("minute").pluralize(item.quantity)}"
        end
        text << " #{item.to_money.format(with_currency: true)}"
        text
      end.compact.join("\n")
    end

    # Private: Converts shared storage megabyte hours consumed to gigabytes rounded to 2 decimal places
    sig { params(megabyte_hours: Billing::Types::NonMoneyNumeric).returns(Billing::Types::NonMoneyNumeric) }
    def gigabytes_used(megabyte_hours)
      megabytes = megabyte_hours / Billing::SharedStorage::ZuoraProduct::ASSUMED_MONTHLY_DAYS / 24

      to_gigabytes(megabytes)
    end

    # Private: Included shared storage in gigabytes rounded to 2 decimal places
    sig { returns(Billing::Types::NonMoneyNumeric) }
    def plan_shared_storage_included_gigabytes
      to_gigabytes(plan&.shared_storage_included_megabytes)
    end

    sig { params(size_in_megabytes: Billing::Types::NonMoneyNumeric).returns(Billing::Types::NonMoneyNumeric) }
    def to_gigabytes(size_in_megabytes)
      (size_in_megabytes.megabytes / 1.gigabyte.to_f).round(2)
    end

    sig { returns(String) }
    def repository_plan_text
      text = []
      text << plan_display_name
      text << "yearly" if yearly?
      text.compact.join(" ")
    end

    sig { returns(String) }
    def plan_display_name
      plan = self.plan
      (plan ? plan.display_name : plan_name)&.titleize || ""
    end

    sig { returns(String) }
    def prorated_yearly_upgrade_text
      if old_plan_name
        "#{old_plan_name.humanize} to #{plan_name.humanize}"
      else
        repository_plan_text
      end
    end

    sig { returns(String) }
    def per_seat_renewal_text
      return business_plan_text if plan&.business?

      "#{pluralize(seats_total, "seat")} (#{per_seat_cost_text})"
    end

    sig { returns(Integer) }
    def additional_seats
      [seats_total - plan&.base_units.to_i, 0].max
    end

    sig { returns(T.nilable(String)) }
    def additional_seats_text
      if additional_seats > 0
        "#{pluralize(additional_seats, "additional seat")} (#{per_seat_cost_text})"
      end
    end

    sig { returns(T.nilable(String)) }
    def base_seats_text
      return unless plan = self.plan
      "#{plan.base_units} included seats" if plan.base_units > 0
    end

    sig { returns(String) }
    def added_data_packs_text
      "#{pluralize(asset_packs_delta, "additional data pack")} (#{data_pack_cost_text})"
    end

    sig { returns(T.nilable(String)) }
    def added_seats_text
      if added_seats?
        "#{pluralize(seats_delta, "additional seat")} (#{per_seat_cost_text})"
      end
    end

    sig { returns(T.nilable(String)) }
    def switch_to_per_seat_text
      if switched_to_per_seat?
        "Switch to #{plan_display_name} (#{pluralize(seats_total, "seat")})"
      end
    end

    sig { returns(String) }
    def per_seat_cost_text
      prorated_cost_text(Billing::Money.new(plan_unit_cost))
    end

    sig { returns(String) }
    def data_pack_cost_text
      prorated_cost_text(Asset::Status.data_pack_unit_price * plan_duration_in_months)
    end

    sig { params(cost: Billing::Money).returns(String) }
    def prorated_cost_text(cost)
      text = []
      text << "#{cost.format(no_cents_if_whole: true)}/#{yearly? ? 'year' : 'month'} each"
      if prorated_charge? && prorated_days_with_fallback > 0
        text << "- prorated for #{pluralize(prorated_days_with_fallback, "day")}"
      end
      text.join(" ")
    end

    sig { returns(T.nilable(GitHub::Plan)) }
    memoize def plan
      plan = GitHub::Plan.find(plan_name, account: billable_entity)
      plan.receipt_effective_on = purchased_at.to_date if plan && purchased_before_munich_launch?
      plan
    end

    sig { returns(T.nilable(GitHub::Plan)) }
    memoize def old_plan
      plan = GitHub::Plan.find(old_plan_name)
      return unless plan

      plan.receipt_effective_on = purchased_at.to_date if purchased_before_munich_launch?
      plan
    end

    sig { returns(Integer) }
    def plan_duration_in_months
      yearly? ? 12 : 1
    end

    sig { returns(Integer) }
    def plan_unit_cost
      plan = self.plan
      return 0 unless plan

      yearly? ? plan.yearly_unit_cost_in_cents : plan.unit_cost_in_cents
    end

    sig { returns(ActiveSupport::TimeWithZone) }
    def service_ends_at
      billing_transaction.service_ends_at || (created_at + plan_duration_in_months.months)
    end

    sig { returns(Integer) }
    def prorated_days_with_fallback
      return 0 unless prorated_charge?
      return prorated_days unless prorated_days.zero?

      # This is a fallback for cases where the prorated days are not saved to the db.
      # This solution is not ideal for all cases (transaction `created_at` can be on
      # the same day the service started or in the future), but is mitigating some
      # common error scenarios when calculating the prorated days on old billing
      # transactions.
      #
      # All new billing transactions from now on should have the correct prorated_days
      # saved to the db when the zuora webhook is processed.
      #
      # See https://github.com/github/gitcoin/issues/4329 for more details.
      (created_at.to_billing_date..service_ends_at.to_billing_date).count
    end

    sig { returns(Date) }
    def munich_plan_release_date
      ::MunichPlan::RELEASE_DATE
    end

    # Internal: formatted text outlining seat count and cost, conditionally
    # including the plan display name
    sig { returns(String) }
    def business_plan_text
      if purchased_before_munich_launch?
        [base_seats_text, additional_seats_text].compact.join(" + ")
      else
        "#{plan_display_name}: #{pluralize(seats_total, "seat")} (#{per_seat_cost_text})"
      end
    end

    # Internal: whether the transaction took place before or after
    # the launch of project munich
    sig { returns(T::Boolean) }
    def purchased_before_munich_launch?
      purchased_at.to_date < munich_plan_release_date
    end

    # Internal: Removes insignificant zeros after the decimal
    sig { params(number: Billing::Types::Numeric, precision: Integer).returns(String) }
    def strip_insignificant_zeros(number, precision: 3)
      number_with_precision(number, precision: precision, strip_insignificant_zeros: true)
    end
  end
end
