# typed: strict
# frozen_string_literal: true

module AzureEXP
  module Experiments
    module Webex
      WEBEX_NAMESPACE = T.let("webex".freeze, String)
      PRICING_VALIDATION_EXP_ID = T.let("aa-test-is-treatment".freeze, String)
    end

    extend Webex
  end
end
