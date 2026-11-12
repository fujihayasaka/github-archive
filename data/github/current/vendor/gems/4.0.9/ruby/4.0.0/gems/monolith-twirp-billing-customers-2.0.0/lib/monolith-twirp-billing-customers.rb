# frozen_string_literal: true

require "monolith_twirp/billing/customers/version"

Dir["#{File.dirname(__FILE__)}/monolith_twirp/**/*_twirp.rb"].each { |file| require file }

module Monolith
  module Twirp
    module Billing
      module Customers
        class Error < StandardError; end
      end
    end
  end
end
