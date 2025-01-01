# typed: strict
# frozen_string_literal: true

require "test_helper"

class AppleAppStore::ReceiptDecoderTest < GitHub::TestCase
  include GitHub::BillingTest

  test "extracts in-app purchase transaction receipts from Apple App Store receipts encoded in ASN.1" do
    receipt = Rails.root.join("test/fixtures/mobile/apple-app-store-receipt.base64")
    receipt_data = File.binread(receipt)
    receipts = AppleAppStore::ReceiptDecoder.parse(base64_encoded_receipt: receipt_data)

    assert_equal receipts.count, 13
    assert_equal Set.new(receipts.map(&:product_id)), Set.new(%w(ProDev CopilotDev))
    assert_equal receipts.map(&:transaction_id), %w(
      2000000520669307
      2000000520673283
      2000000520676422
      2000000520678536
      2000000520684332
      2000000520688910
      2000000520693031
      2000000520695833
      2000000520697917
      2000000520699858
      2000000520701810
      2000000520704313
      2000000522850902
    )
    assert_equal Set.new(receipts.map(&:original_transaction_id)), Set.new(%w(2000000520669307 2000000522850902))
  end
end
