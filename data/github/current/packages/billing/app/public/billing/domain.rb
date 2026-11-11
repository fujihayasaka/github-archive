# typed: strict
# frozen_string_literal: true

module Billing
  class Domain < GH::Domain::Base
    accessor Billing::Domain::PaymentAuthorizations
  end
end
