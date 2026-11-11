# typed: strict
# frozen_string_literal: true

class Licensing::Vss::AgreementBackfillMessage

  sig { returns(T::Hash[Symbol, T.untyped]) }
  attr_reader :body

  sig { params(enterprise_agreement_number: String).void }
  def initialize(enterprise_agreement_number:)
    @body = T.let({ enterpriseAgreementNumber: enterprise_agreement_number }, T::Hash[Symbol, T.untyped])
  end

  sig { returns(String) }
  def serialize_message
    body.to_json
  end
end
