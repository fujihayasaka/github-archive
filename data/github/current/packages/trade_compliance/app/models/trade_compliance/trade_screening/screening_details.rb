# typed: strict
# frozen_string_literal: true

module TradeCompliance::TradeScreening
  # The screening details object that's required as part of building a request to the
  # Microsoft Trade Screening external service.
  class ScreeningDetails

    sig { params(account_type: AccountType, external_id: String).void }
    def initialize(account_type:, external_id:)
      @account_type = account_type
      @external_id = external_id
      @customer_details = T.let([], T::Array[CustomerDetails])
    end

    sig { params(details: CustomerDetails).returns(TradeCompliance::TradeScreening::ScreeningDetails) }
    def add_customer_details(details:)
      raise ScreeningDetailsError.new("Customer details id, #{details.id}, must be unique") if customer_details.any? { |customer_detail| customer_detail.id == details.id }
      customer_details << details
      self
    end

    sig { returns(T::Array[String]) }
    def validate
      [
        validate_external_id,
        validate_customer_details,
      ].flatten.compact_blank
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_hash
      errors = validate
      raise ScreeningDetailsError.new("external id: #{external_id}, errors: #{errors.join(", ")}") if errors.any?

      {
        ScrReqsEnv: {
          EId: SecureRandom.uuid,
          DT: Time.now.utc.iso8601,
          CohortCode: GitHub.sdn_cohort_code,
          Prov: "GITHUB",
          CustTyp: account_type.serialize,
          ExternalRefID: external_id,
          ScrReqs: {
            ScrReq: customer_details.map { |customer_detail| customer_detail.to_hash(account_type: account_type).compact_blank },
          },
        },
      }.compact_blank
    end

    private

    sig { returns(AccountType) }
    attr_reader :account_type
    sig { returns(String) }
    attr_reader :external_id
    sig { returns(T::Array[CustomerDetails]) }
    attr_reader :customer_details

    sig { returns(T.nilable(String)) }
    def validate_external_id
      max = 40
      return if external_id.present? && external_id.length <= max

      "External id must be a string with a maximum of #{max} characters"
    end

    sig { returns(T::Array[String]) }
    def validate_customer_details
      return ["Must add at least one customer details"] if customer_details.empty?
      # TODO: This is (hopefully) a temporary requirement, see: https://github.com/github/trade-compliance/issues/1432
      individual_missing_required_id = account_type == AccountType::Individual && customer_details.none? { |customer_detail| customer_detail.id == "IndName_IndAddr" }
      return ["Must add at least one customer details with ID 'IndName_IndAddr'"] if individual_missing_required_id

      customer_details.flat_map do |customer_detail|
        customer_detail.validate(account_type: account_type).map { |error| "Customer details id #{customer_detail.id}: #{error}" }
      end
    end
  end
end
