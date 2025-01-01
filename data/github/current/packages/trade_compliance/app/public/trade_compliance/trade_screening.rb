# typed: strict
# frozen_string_literal: true

module TradeCompliance::TradeScreening
  class ApiServiceAuthenticationError < StandardError; end
  class ApiServiceBadResponseError < StandardError; end
  class ApiServiceError < StandardError; end
  class CustomerDetailsError < StandardError; end
  class EisBusResponseParsingError < StandardError; end
  class LiveResponseParsingError < StandardError; end
  class LiveResponseEmptyError < StandardError; end
  class ScreeningDetailsError < StandardError; end
  class SDNAuthenticationError < StandardError; end
  class UnknownActorError < StandardError; end

  class AccountType < T::Enum
    enums do
      Individual = new("IND")
      Business = new("ORG")
    end
  end
end
