# typed: strict
# frozen_string_literal: true

module AppleAppStore
  # The data struct representing the fields we care about from an in-app purchase receipt from Apple.
  # The class ReceiptDecoder is able to parse the receipt and return an array of these structs. See the
  # documentation here on where the fields get populated from:
  # https://developer.apple.com/library/archive/releasenotes/General/ValidateAppStoreReceipt/Chapters/ReceiptFields.html
  class InAppReceipt < T::Struct
    const :product_id, String
    const :transaction_id, String
    const :original_transaction_id, String
  end
end
