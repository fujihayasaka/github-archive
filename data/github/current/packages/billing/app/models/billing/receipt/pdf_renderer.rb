# typed: strict
# frozen_string_literal: true

require "prawn/table"

module Billing
  class Receipt::PdfRenderer
    extend T::Sig

    CELL_VERTICAL_PADDING = 10
    LINESPACING = 4

    SERVICE_DATES_FORMAT = "%b %-d, %Y"

    class ItemRow < T::Struct
      extend T::Sig

      const :title, String
      const :formatted_amount, String
      const :quantity, T.nilable(BigDecimal)
      const :service_period, T.nilable(String)

      sig do
        params(pdf: Prawn::Document).returns(
          T::Array[T.any(
            T::Hash[Symbol, T.untyped],
            Prawn::Table
          )])
      end
      def to_data(pdf)
        charge_summary = T.let([[{
          content: formatted_amount,
          font_style: :bold,
          padding: 0,
          leading: LINESPACING,
        }]], T::Array[T::Array[T.untyped]])

        if service_period.present?
          charge_summary << [{
            content: service_period,
            size: 10,
            text_color: "5A5A5A",
            padding: [4, 0, 0, 0]
          }]
        end

        data = [
          { content: title, valign: :center },
          # * The parent's table width is set as [140, 352] for a total of 492 units.
          #   Setting the column to the width of the parent ensures prawn doesn't attempt
          #   to calculate a width higher than that's available for the entire table.
          # * pdf is set to unsafe because make_table is added as method through
          #   Prawn::Document.extensions by prawn-table gem.
          T.unsafe(pdf).make_table(charge_summary, cell_style: { borders: [] }, column_widths: [352])
        ]
      end
    end

    sig do
      params(
        receipt: Billing::Receipt,
        show_email_address: T::Boolean,
        viewer: T.nilable(User)
      ).void
    end
    def initialize(receipt, show_email_address: true, viewer: nil)
      @receipt = receipt
      @show_email_address = show_email_address
      @viewer = viewer
    end

    # Public: Returns a PDF of the receipt.
    sig { returns(String) }
    def render
      svg_logo = File.open("#{Rails.root}/public/images/modules/pricing/pdf-logo.svg").read
      svg_thankyou = File.open("#{Rails.root}/public/images/modules/pricing/thankyou.svg").read

      login_or_slug = receipt.billable_entity.to_s
      email = receipt.billable_entity.try(:billing_email)

      document = Prawn::Document.new({ margin: [50, 60, 50, 60] }) do |pdf|
        # Page width: 492

        pdf.font_families["Arial-Unicode"] = {
          normal: "#{Rails.root}/lib/assets/fonts/Arial Unicode Bold.ttf",
          bold: "#{Rails.root}/lib/assets/fonts/Arial Unicode Bold.ttf",
        }
        pdf.font_families["Helvetica"] = {
          normal: "#{Rails.root}/lib/assets/fonts/Helvetica.dfont",
          bold: "#{Rails.root}/lib/assets/fonts/Helvetica Bold.ttf",
        }

        pdf.line_width = 0.3
        pdf.fallback_fonts ["Arial-Unicode"]

        if receipt.is_refund?
          pdf.image "#{Rails.root}/public/images/modules/pricing/github-mark-refund.png", position: :center, width: 110
        else
          pdf.image "#{Rails.root}/public/images/modules/pricing/github-mark.png", position: :center, width: 80
        end

        pdf.move_down 15

        pdf.font_size 11
        pdf.stroke_color "aaaaaa"
        pdf.fill_color "777777"
        pdf.horizontal_line 216, 276

        pdf.move_down 20

        pdf.fill_color "333333"

        if receipt.is_refund?
          pdf.text("You've been issued a refund! The amount will be credited to your credit card ending with #{receipt.last_four}.", leading: 5, inline_format: true)
        elsif receipt.sponsorship_only_transaction? && receipt.sponsorship_line_items_displayable?
          pdf.text(receipt.sponsorship_only_text, leading: 5, inline_format: true)
        elsif receipt.prorated_charge? || receipt.job_posting?
          pdf.text("Thanks for your purchase!", leading: 5, inline_format: true)
        else
          pdf.text "We received payment for your GitHub.com subscription. Thanks for your business!",
            leading: 5, inline_format: true
        end

        pdf.text "Questions? Visit <link href='#{GitHub.contact_support_url}'><color rgb='0088cc'>#{GitHub.contact_support_url}</color></link>.",
          leading: 5, inline_format: true

        pdf.move_down 15

        data = []

        data << ["Date", "<b>#{receipt.purchased_at.strftime("%Y-%m-%d %I:%M%p %Z")}</b>"]
        data << ["Account billed", "<b>#{login_or_slug}</b>" + (show_email_address ? " (#{email})" : "")]
        if receipt.vat_code.present?
          data << ["VAT/GST Identification Number", "<b>#{receipt.vat_code}</b>"]
        end

        header_data = []

        header_data << ["Transaction ID", "<b>#{receipt.transaction_id}</b>"]
        header_data << ["Sale Transaction ID", "<b>#{receipt.sale_transaction_id}</b>"] if receipt.is_refund?
        if receipt.display_service_through? && !receipt.generic_line_item_feature_enabled_for_viewer?
          header_data << ["For service through", "<b>#{receipt.service_ends_on}</b>"]
        end

        if receipt.display_payment_identifier?
          header_data << [
            "#{ receipt.is_refund? ? "Refunded" : "Charged" } to",
            "<b>#{receipt.payment_type}</b> (#{receipt.payment_identifier})"
          ]
        end

        if receipt.extra.present?
          header_data << ["Extra billing information\n<font size='10'>(Added by #{login_or_slug})</font>", "<b>#{receipt.extra}</b>"]
        end

        if receipt.generic_line_item_feature_enabled_for_viewer?
          data += header_data
          data += generic_line_items(pdf)
        else
          data += product_category_grouped_line_items(pdf)
        end

        if receipt.marketplace_line_items_displayable?
          # TODO: Currently all line items are built up here for text.
          # We may need to separate the service dates per line item but not display them under each as it would
          # likely be too large and redundant
          data << ["Marketplace Apps", "<b>#{receipt.marketplace_line_items_text}</b>"]
          data << ["Marketplace Amount", "<b>#{receipt.marketplace_amount.format(with_currency: true)}</b>"]
        end

        if receipt.sponsorship_line_items_displayable?
          self.first_sponsor_row = data.length
          receipt.sponsorship_line_items.each_with_index do |item, i|
            first_column = i.zero? ? "Sponsorships" : ""
            data << [first_column, "<b>#{item.receipt_text}</b>"]
          end
          data << ["Sponsorship Amount", "<b>#{receipt.sponsorship_amount_excluding_fees.format(with_currency: true) +
              receipt.sponsorship_prorated_message}</b>"]
          unless receipt.sponsorship_fees_amount.zero?
            data << ["Sponsorship Fees", "<b>#{receipt.sponsorship_fees_amount.format(with_currency: true)}</b>"]
          end
        end
        data << ["Refund Amount", "<b>#{receipt.amount.abs.format(with_currency: true)}</b>"] if receipt.is_refund?
        if receipt.display_tax?
          data << ItemRow.new(
            title: "Tax",
            formatted_amount: receipt.tax_amount.format(with_currency: true),
          ).to_data(pdf)
        end
        data << ["Total", "<b>#{receipt.amount.abs.format(with_currency: true)}*</b>"]

        if !receipt.generic_line_item_feature_enabled_for_viewer?
          data += header_data
        end

        pdf.table data, column_widths: [140, 352], cell_style: {
          borders: [:top],
          border_width: 0.3,
          border_color: "dddddd",
          inline_format: true,
          padding: [CELL_VERTICAL_PADDING, 0, CELL_VERTICAL_PADDING, 0],
        } do |table|
          # Override borders for the first row
          table.row(0).borders = []
          table.cells.leading = 4

          # Override some cell borders and padding to make sponsors line items look as though they're one row
          # but really they're many rows so that we can have more than one page of them
          first_sponsor_row = self.first_sponsor_row
          if first_sponsor_row && receipt.sponsorship_line_items.count > 1
            last_sponsor_row = first_sponsor_row + receipt.sponsorship_line_items.count - 1

            table.row(first_sponsor_row).padding = [CELL_VERTICAL_PADDING, 0, 0, 0]
            table.rows((first_sponsor_row + 1)..last_sponsor_row).borders = []
            table.rows((first_sponsor_row + 1)..(last_sponsor_row - 1)).padding = [LINESPACING, 0, 0, 0]
            table.row(last_sponsor_row).padding = [LINESPACING, 0, CELL_VERTICAL_PADDING, 0]
          end
        end

        # Start a new page if content is close to the bottom edge
        footer_height = 100
        if pdf.cursor < footer_height
          pdf.start_new_page
        end

        # Footer here
        footer_with_thankyou_height = 170
        pdf.svg svg_thankyou, at: [0, 160], width: 180 if pdf.cursor > footer_with_thankyou_height
        pdf.svg svg_logo, at: [0, 100], width: 40
        pdf.move_down 15

        pdf.font_size 10
        pdf.fill_color "999999"

        pdf.table [["GitHub, Inc.\n88 Colin P. Kelly Jr. Street\nSan Francisco, CA 94107\nUnited States",
          GitHub.contact_support_url]], cell_style: {
            borders: [], padding: 0
          }, column_widths: [150, 150] do |table|
          table.row(0).leading = 4
        end

        pdf.move_down 10

        vat_line  = "* VAT/GST paid directly by GitHub, where applicable"
        pdf.draw_text vat_line, at: [0, 0], size: 10
      end

      document.render
    end

    private

    sig { returns(T.nilable(Integer)) }
    attr_accessor :first_sponsor_row

    sig { returns(T.nilable(User)) }
    attr_reader :viewer

    sig { returns(Billing::Receipt) }
    attr_reader :receipt

    sig { returns(T::Boolean) }
    attr_reader :show_email_address

    # Renders line items as is without applying any grouping and omitting quantity.
    sig { params(pdf: T.untyped).returns(T::Array[T.any(T::Array[String], ItemRow)]) }
    def generic_line_items(pdf)
      login_or_slug = receipt.billable_entity.to_s
      email = receipt.billable_entity.try(:billing_email)

      data = []

      # Charge Rows
      if receipt.generic_line_items_displayable?
        data << [
          { content: "Description", font_style: :bold },
          { content: "Amount", font_style: :bold }
        ]
      end

      receipt.generic_line_items.each do |item|
        data << ItemRow.new(
          title: item.description,
          formatted_amount: item.to_money.format(with_currency: true),
          service_period: item.formatted_service_period(format: SERVICE_DATES_FORMAT, separator: "-")
        ).to_data(pdf)
      end

      data
    end

    # Renders line items grouped by product category (i.e. GitHub Packages, GitHub Actions, etc.)
    sig { params(pdf: T.untyped).returns(T::Array[T.any(T::Array[String], ItemRow)]) }
    def product_category_grouped_line_items(pdf)
      login_or_slug = receipt.billable_entity.to_s
      email = receipt.billable_entity.try(:billing_email)

      data = []

      if receipt.display_github_plan?
        data << ["GitHub Plan", "<b>#{receipt.plan_summary}</b>"]
      end

      if receipt.marketplace_line_items_displayable? || receipt.sponsorship_line_items_displayable?
        data << ["Plan Amount", "<b>#{receipt.plan_amount.format(with_currency: true)}</b>"]
      end

      data << ["Plan Discount", "<b>#{receipt.annual_discount_text}</b>"] if receipt.has_annual_discount?
      data << ["Data", "<b>#{receipt.data_packs_addon_text}</b>"] if receipt.plan_renewal_with_data_packs?

      if receipt.show_actions_row?
        data << ItemRow.new(
          title: "GitHub Actions",
          formatted_amount: receipt.actions_line_items_text.to_s,
          service_period: receipt.actions_line_items.detect(&:service_period?)&.formatted_service_period(
            format: SERVICE_DATES_FORMAT, separator: "-"
          )
        ).to_data(pdf)
      end

      if receipt.show_packages_row?
        data << ItemRow.new(
          title: "GitHub Packages",
          formatted_amount: receipt.packages_transfer_line_items_text.to_s,
          service_period: receipt.package_registry_transfer_line_items.detect(&:service_period?)&.formatted_service_period(
            format: SERVICE_DATES_FORMAT, separator: "-"
          )
        ).to_data(pdf)
      end

      if receipt.show_shared_storage_row?
        data << ItemRow.new(
          title: "Actions/Packages Storage",
          formatted_amount: receipt.shared_storage_line_items_text.to_s,
          service_period: receipt.shared_storage_line_items.detect(&:service_period?)&.formatted_service_period(
            format: SERVICE_DATES_FORMAT, separator: "-"
          )
        ).to_data(pdf)
      end

      if receipt.codespaces_line_items_displayable?
        data << ItemRow.new(
          title: "Codespaces",
          formatted_amount: receipt.codespaces_line_items_text,
        ).to_data(pdf)

        data << ItemRow.new(
          title: "Codespaces Amount",
          formatted_amount: receipt.codespaces_amount.format(with_currency: true),
          service_period: receipt.codespaces_line_items.detect(&:service_period?)&.formatted_service_period(
            format: SERVICE_DATES_FORMAT, separator: "-"
          )
        ).to_data(pdf)
      end

      if receipt.copilot_line_items_displayable?
        data << ItemRow.new(
          title: "GitHub Copilot",
          formatted_amount: receipt.copilot_formatted_amount,
          service_period: T.must(receipt.copilot_line_item).formatted_service_period(
            format: SERVICE_DATES_FORMAT, separator: "-"
          )
        ).to_data(pdf)
      end

      if receipt.show_metered_copilot_row?
        # Description row
        data << ItemRow.new(
          title: "GitHub Copilot",
          formatted_amount: receipt.metered_copilot_text,
        ).to_data(pdf)

        # Amount row
        data << ItemRow.new(
          title: "GitHub Copilot Amount",
          formatted_amount: receipt.metered_copilot_amount.format(with_currency: true),
          service_period: receipt.metered_copilot_line_items.detect(&:service_period?)&.formatted_service_period(
            format: SERVICE_DATES_FORMAT, separator: "-"
          )
        ).to_data(pdf)
      end

      if receipt.advanced_security_line_items_displayable?
        data << ItemRow.new(
          title: "GitHub Advanced Security",
          formatted_amount: receipt.advanced_security_formatted_amount.to_s,
          service_period: receipt.advanced_security_line_items.detect(&:service_period?)&.formatted_service_period(
            format: SERVICE_DATES_FORMAT, separator: "-"
          )
        ).to_data(pdf)
      end

      data
    end
  end
end
