# typed: true
# frozen_string_literal: true

module GitHub
  module Billing
    module Api
      autoload :FakeServer, "github/billing/meuse/fake_server"
      autoload :FakeServer, "github/billing/billing_platform/fake_server"
    end
  end
end
