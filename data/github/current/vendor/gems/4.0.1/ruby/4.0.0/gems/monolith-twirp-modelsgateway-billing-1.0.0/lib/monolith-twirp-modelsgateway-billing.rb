# frozen_string_literal: true

require "monolith_twirp/modelsgateway/billing/version"

Dir["#{File.dirname(__FILE__)}/monolith_twirp/**/*_twirp.rb"].each { |file| require file }

module Monolith
  module Twirp
    module Modelsgateway
      module Billing
        class Error < StandardError; end
      end
    end
  end
end
