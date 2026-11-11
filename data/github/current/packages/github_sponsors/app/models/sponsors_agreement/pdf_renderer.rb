# typed: true
# frozen_string_literal: true

require "prawn/table"

class SponsorsAgreement::PdfRenderer
  include GitHub::Memoizer

  DOCUMENT_OPTIONS = { margin: [50, 60, 50, 60] }.freeze
  ARIAL_FONT_SETTINGS = {
    normal: "#{Rails.root}/lib/assets/fonts/Arial Unicode Bold.ttf",
    bold: "#{Rails.root}/lib/assets/fonts/Arial Unicode Bold.ttf",
  }.freeze
  HELVETICA_FONT_SETTINGS = {
    normal: "#{Rails.root}/lib/assets/fonts/Helvetica.dfont",
    bold:   "#{Rails.root}/lib/assets/fonts/Helvetica Bold.ttf",
  }.freeze

  MARKDOWN_MATCHERS = {
    /^# (.+)/                  => '<font size="17"><b>\1</b></font>', # Header 1
    /^## (.+)/                 => '<font size="16"><b>\1</b></font>', # Header 2
    /^### (.+)/                => '<font size="15"><b>\1</b></font>', # Header 3
    /^#### (.+)/               => '<font size="14"><b>\1</b></font>', # Header 4
    /^##### (.+)/              => '<font size="13"><b>\1</b></font>', # Header 5
    /^###### (.+)/             => '<font size="12"><b>\1</b></font>', # Header 6
    /\[([^\[]+)\]\(([^\)]+)\)/ => '<link href="\2">\1</link>',        # Link
    /(\*\*|__)(.*?)\1/         => '<b>\2</b>',                        # Bold
    /(\*|_)(.*?)\1/            => '<i>\2</i>',                        # Italic
    /\~\~(.*?)\~\~/            => '<strikethrough>\1</strikethrough>' # Strikethrough
  }

  def initialize(agreement:)
    @agreement = agreement
  end

  attr_reader :agreement

  def render
    document.render
  end

  private

  memoize def document
    Prawn::Document.new(DOCUMENT_OPTIONS) do |pdf|
      pdf.font_families["Arial-Unicode"] = ARIAL_FONT_SETTINGS
      pdf.font_families["Helvetica"] = HELVETICA_FONT_SETTINGS

      pdf.line_width = 0.3
      pdf.fallback_fonts ["Arial-Unicode"]

      pdf.image "#{Rails.root}/public/static/images/modules/open_graph/github-mark.png", position: :center, width: 70
      pdf.move_down 15
      pdf.text "GitHub Invoiced Sponsor Agreement", size: 17, align: :center

      pdf.move_down 20

      pdf.stroke_color "aaaaaa"
      pdf.stroke_horizontal_line 216, 276

      pdf.move_down 20

      pdf.fill_color "333333"

      body_text = MARKDOWN_MATCHERS.inject(agreement.body) do |final_string, (markdown_matcher, prawn_tag)|
        final_string.gsub(markdown_matcher, prawn_tag)
      end
      pdf.text body_text, inline_format: true
    end
  end
end
