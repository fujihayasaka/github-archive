# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class StripeFraudType < Platform::Enums::Base
      description "The type of fraud labelled by the issuer."

      # Source: https://stripe.com/docs/api/radar/early_fraud_warnings/object#early_fraud_warning_object-fraud_type
      value "CARD_NEVER_RECEIVED", "Card never received", value: "card_never_received"
      value "FRAUDULENT_CARD_APPLICATION", "The card application was fraudulent", value: "fraudulent_card_application"
      value "MADE_WITH_COUNTERFEIT_CARD", "The transaction was made with a counterfeit card", value: "made_with_counterfeit_card"
      value "MADE_WITH_LOST_CARD", "The transaction was made with a lost card", value: "made_with_lost_card"
      value "MADE_WITH_STOLEN_CARD", "The transaction was made with a stolen card", value: "made_with_stolen_card"
      value "MISC", "Miscellaneous", value: "misc"
      value "UNAUTHORIZED_USE_OF_CARD", "The card was used in an unauthorized manner", value: "unauthorized_use_of_card"
    end
  end
end
