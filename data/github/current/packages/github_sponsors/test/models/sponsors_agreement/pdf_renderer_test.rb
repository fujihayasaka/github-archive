
# typed: true
# frozen_string_literal: true

require "test_helper"
require "pdf-reader"

class SponsorsAgreementPdfRendererTest < GitHub::TestCase
  fixtures do
    @agreement = create(:sponsors_agreement, :invoiced_sponsor, body: "This is the agreement body")
  end

  setup do
    skip unless GitHub.sponsors_enabled?
  end

  def pdf_text_for(agreement)
    renderer = SponsorsAgreement::PdfRenderer.new(agreement: agreement)
    T.must(PDF::Reader.new(StringIO.new(renderer.render)).pages.first).text
  end

  test "includes title" do
    text = pdf_text_for(@agreement)
    assert_includes text, "GitHub Invoiced Sponsor Agreement"
  end

  test "includes agreement body text" do
    text = pdf_text_for(@agreement)
    assert_includes text, @agreement.body
  end
end
