# typed: strict
# frozen_string_literal: true

module AppleAppStore
  class ReceiptDecoder
    extend T::Sig

    class DecodeError < StandardError
    end

    # See also: https://developer.apple.com/library/archive/releasenotes/General/ValidateAppStoreReceipt/Chapters/ReceiptFields.html
    IN_APP_RECEIPT_FIELD_TYPE = 17
    PRODUCT_ID_FIELD_TYPE = 1702
    TRANSACTION_ID_FIELD_TYPE = 1703
    ORIGINAL_TRANSACTION_ID_FIELD_TYPE = 1705

    # Convenience method to ease consumption/simplify callers.
    # This should be the primary surface area for almost all consumers of this class.
    sig { params(base64_encoded_receipt: String).returns(T::Array[InAppReceipt]) }
    def self.parse(base64_encoded_receipt:)
      new(base64_encoded_receipt:).in_app_receipts
    end

    sig { params(base64_encoded_receipt: String).void }
    def initialize(base64_encoded_receipt:)
      asn1_receipt = OpenSSL::ASN1.decode(Base64.decode64(base64_encoded_receipt))

      receipt_signed_data = extract_receipt_signed_data(asn1_receipt)
      data = extract_receipt_data(receipt_signed_data)
      encoded_app_receipt_data = extract_encoded_app_receipt(data)

      @decoded_receipt = T.let(OpenSSL::ASN1.decode(encoded_app_receipt_data), OpenSSL::ASN1::ASN1Data)
    end

    # Returns an array containing all in-app purchase receipts based on the in-app purchase transactions present in the input base-64 receipt-data.
    sig { returns(T::Array[InAppReceipt]) }
    def in_app_receipts
      in_app_receipt_data = decoded_receipt.value.select do |item|
        item.value[0].value.to_i == IN_APP_RECEIPT_FIELD_TYPE
      end

      in_app_receipt_data.filter_map do |item|
        # we expect that each item should contain 3 sub-items and skip the other ones if we encounter one.
        # In a valid receipt coming from the device, we of course don't expect this to be happen.
        # More information regarding the shape of the expected receipt data and how to decode it could be
        # found here: https://www.objc.io/issues/17-security/receipt-validation
        next unless item.value.is_a?(Array)
        next if item.value.length != 3

        value = OpenSSL::ASN1.decode(item.value[2].value).value
        product_id = select_receipt_attribute(value, PRODUCT_ID_FIELD_TYPE)
        transaction_id = select_receipt_attribute(value, TRANSACTION_ID_FIELD_TYPE)
        original_transaction_id = select_receipt_attribute(value, ORIGINAL_TRANSACTION_ID_FIELD_TYPE)
        InAppReceipt.new(product_id:, transaction_id:, original_transaction_id:)
      end
    end

    private

    sig { returns(OpenSSL::ASN1::ASN1Data) }
    attr_reader :decoded_receipt

    # Extracts signed receipt data from within receipt container, and validates its format.
    sig { params(receipt: OpenSSL::ASN1::ASN1Data).returns(OpenSSL::ASN1::ASN1Data) }
    def extract_receipt_signed_data(receipt)
      # We expect the incoming receipt to be structured exactly as outlined here:
      # https://www.objc.io/issues/17-security/receipt-validation
      # These assertions are here to help reinforce the knowledge around what our expectation of the
      # data shape should be. In valid receipts, we don't expect these assertions to fail.
      raise DecodeError.new("receipt container is not an array") unless receipt.value.is_a?(Array)
      raise DecodeError.new("receipt contains unknown additional data") if receipt.value.length != 2
      raise DecodeError.new("receipt does not contain pkcs7-signedData") if receipt.value[0].value != "pkcs7-signedData"

      receipt_signed_data = receipt.value[1]

      raise DecodeError.new("receipt signed data is not an array") unless receipt_signed_data.value.is_a?(Array)

      if receipt_signed_data.tag_class == :CONTEXT_SPECIFIC && receipt_signed_data.value.length == 1
        receipt_signed_data
      else
        raise DecodeError.new("receipt signed data is malformed")
      end
    end

    sig { params(receipt_signed_data: OpenSSL::ASN1::ASN1Data).returns(OpenSSL::ASN1::ASN1Data) }
    def extract_receipt_data(receipt_signed_data)
      raise DecodeError.new("receipt signed data is not an array") unless receipt_signed_data.value.is_a?(Array)
      raise DecodeError.new("receipt signed data is not the correct length") unless receipt_signed_data.value.length > 0

      receipt_signed_data.value[0]
    end

    # Extracts the encoded app receipt according to Apple's spec.
    # Note that the app receipt contains _many_ in-app purchase transactions, not just one.
    sig { params(data: OpenSSL::ASN1::ASN1Data).returns(String) }
    def extract_encoded_app_receipt(data)
      raise DecodeError.new("encoded app receipt data is not an array") unless data.value.is_a?(Array)
      raise DecodeError.new("encoded app receipt contains unknown additional data") unless data.value.length > 3

      # other fields are not used but noted for reference
      _signature, _signing_algorithm, app_receipt_seq, _signing_certs_chain_a, _signing_certs_chain_b = data.value

      raise DecodeError.new("app receipt is not an array") unless app_receipt_seq.value.is_a?(Array)
      raise DecodeError.new("app receipt is not the correct length") if app_receipt_seq.value.length < 2

      unless app_receipt_seq.value[0].value == "pkcs7-data" &&
             app_receipt_seq.value[1].is_a?(OpenSSL::ASN1::ASN1Data) &&
             app_receipt_seq.value[1].tag_class == :CONTEXT_SPECIFIC &&
             app_receipt_seq.value[1].value.is_a?(Array) &&
             app_receipt_seq.value[1].value.length == 1 &&
             app_receipt_seq.value[1].value[0].is_a?(OpenSSL::ASN1::OctetString)
        raise DecodeError.new("cannot extract encoded app receipt from receipt data")
      end

      app_receipt_seq.value[1].value[0].value
    end

    # Selects the `value` for a given type from an ASN.1 SEQUENCE that matches Apple's format for receipt attributes
    # ReceiptAttribute ::= SEQUENCE {
    #     type    INTEGER,
    #     version INTEGER,
    #     value   OCTET STRING
    # }
    sig { params(asn1_seq: T::Array[OpenSSL::ASN1::ASN1Data], type: Integer).returns(String) }
    def select_receipt_attribute(asn1_seq, type)
      value = asn1_seq.lazy.filter_map do |item|
        next unless item.value.is_a?(Array)
        next if item.value.length != 3

        OpenSSL::ASN1.decode(item.value[2].value).value if item.value[0].value.to_i == type
      end.first

      raise DecodeError.new("receipt attribute not found for type #{type}") if value.nil?

      value
    end
  end
end
