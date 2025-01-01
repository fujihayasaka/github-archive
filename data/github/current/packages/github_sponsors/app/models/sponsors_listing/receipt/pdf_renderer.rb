# typed: strict
# frozen_string_literal: true

require "prawn/table"

class SponsorsListing::Receipt::PdfRenderer
  include GitHub::Memoizer

  MONEY_FORMAT_OPTIONS = T.let({ no_cents_if_whole: false }.freeze, T::Hash[Symbol, T::Boolean])
  DOCUMENT_OPTIONS = T.let({ margin: [50, 60, 50, 60] }.freeze, T::Hash[Symbol, T::Array[Integer]])
  ARIAL_FONT_SETTINGS = T.let({
    normal: "#{Rails.root}/lib/assets/fonts/Arial Unicode Bold.ttf",
    bold: "#{Rails.root}/lib/assets/fonts/Arial Unicode Bold.ttf",
  }.freeze, T::Hash[Symbol, String])
  HELVETICA_FONT_SETTINGS = T.let({
    normal: "#{Rails.root}/lib/assets/fonts/Helvetica.dfont",
    bold:   "#{Rails.root}/lib/assets/fonts/Helvetica Bold.ttf",
  }.freeze, T::Hash[Symbol, String])
  TOTAL_SPONSORSHIP_LABEL = "Sponsorship Amount"

  sig { returns(SponsorsListing::Receipt) }
  attr_reader :receipt

  sig { params(receipt: SponsorsListing::Receipt).void }
  def initialize(receipt)
    @receipt = receipt
  end

  sig { returns(String) }
  def render
    document.render
  end

  private

  sig { returns(Prawn::Document) }
  memoize def document
    header_data = sponsor_header_data
    payout_data = sponsor_payout_data
    total_payout = format_money(receipt.total_payout)
    currency_code = receipt.total_payout.currency.iso_code
    svg_logo = File.open("#{Rails.root}/public/images/modules/pricing/pdf-logo.svg").read

    Prawn::Document.new(DOCUMENT_OPTIONS) do |pdf|
      pdf.font_families["Arial-Unicode"] = ARIAL_FONT_SETTINGS
      pdf.font_families["Helvetica"] = HELVETICA_FONT_SETTINGS

      pdf.line_width = 0.3
      pdf.fallback_fonts ["Arial-Unicode"]

      pdf.fill_rectangle [65,  pdf.cursor],  pdf.bounds.width, 25

      pdf.move_down 60
      pdf.svg svg_logo, at: [0,  pdf.cursor], width: 150

      pdf.move_down 50
      header_y_start = pdf.cursor

      pdf.bounding_box([0, header_y_start], width: 150, height: 93) do
        pdf.text "GitHub, Inc.", leading: 5, style: :bold
        pdf.text "88 Colin P Kelly Jr St", leading: 5
        pdf.text "San Francisco, CA 94107", leading: 5
        pdf.text "United States", leading: 5
      end

      header_y_end = pdf.cursor
      pdf.move_cursor_to header_y_start

      pdf.table(header_data, position: 160, column_widths: [140, 192]) do |table|
        table.cells.borders = []
        table.column(0).padding = [0, 10, 5, 0]
        table.column(0).font_style = :bold
        table.column(0).align = :right
        table.column(1).padding = [0, 0, 5, 15]
      end

      pdf.move_cursor_to header_y_end

      pdf.move_down 50
      pdf.bounding_box([0,  pdf.cursor], width:  pdf.bounds.width, height: 150) do
        pdf.stroke_bounds

        pdf.move_down 20
        pdf.table(payout_data, column_widths: [pdf.bounds.width / 2,  pdf.bounds.width / 2]) do |table|
          table.cells.borders = []
          table.column(0).padding = [5, 5, 5, 25]
          table.column(1).padding = [5, 25, 5, 5]
          table.column(1).align = :right
        end
      end

      pdf.bounding_box([0,  pdf.cursor], width:  pdf.bounds.width, height: 70) do
        pdf.stroke_bounds

        pdf.move_down 20
        data = [
          ["Total Amount of Sponsorship through GitHub Sponsors Program (#{currency_code})", total_payout]
        ]
        pdf.table(
          data,
          column_widths: [pdf.bounds.width / 2, pdf.bounds.width / 2],
          cell_style: { leading: 5, valign: :center },
        ) do |table|
          table.cells.borders = []
          table.cells.font_style = :bold
          table.column(0).padding = [0, 5, 5, 25]
          table.column(1).padding = [0, 25, 5, 5]
          table.column(1).align = :right
        end
      end

      pdf.move_down 15
      pdf.bounding_box([10,  pdf.cursor], width: pdf.bounds.width - 10) do
        pdf.text "This is a report of the payments our records indicate you received from your sponsors through the " \
        "GitHub Sponsors Program during the above Statement Period.", leading: 5
      end
    end
  end

  sig { returns(T::Array[T::Array[String]]) }
  memoize def sponsor_header_data
    tax_id = receipt.tax_id
    address1 = receipt.sponsorable_address1
    address2 = receipt.sponsorable_address2
    formatted_statment_period = statement_period

    header_data = T.let([["Maintainer:", maintainer_description]], T::Array[T::Array[String]])
    header_data << ["", address1] if address1.present?
    header_data << ["", address2] if address2.present?
    header_data << ["Statement Date:", format_date(Date.current)]

    if formatted_statment_period.present?
      header_data << ["Statement Period:", formatted_statment_period]
    end

    header_data << ["Tax ID:", tax_id] if tax_id.present?
    header_data
  end

  sig { returns(String) }
  def maintainer_description
    "@#{receipt.sponsorable_login}"
  end

  sig { returns(String) }
  memoize def statement_period
    "#{format_date(receipt.start_date)} - #{format_date(receipt.end_date)}"
  end

  sig { params(date: T.any(Date, Time)).returns(String) }
  def format_date(date)
    date.strftime("%b %-d, %Y")
  end

  sig { params(money: Billing::Money).returns(String) }
  def format_money(money)
    money.format(MONEY_FORMAT_OPTIONS)
  end

  sig { returns(T::Array[T::Array[String]]) }
  memoize def sponsor_payout_data
    [[TOTAL_SPONSORSHIP_LABEL, format_money(receipt.total_sponsorship)]]
  end
end
