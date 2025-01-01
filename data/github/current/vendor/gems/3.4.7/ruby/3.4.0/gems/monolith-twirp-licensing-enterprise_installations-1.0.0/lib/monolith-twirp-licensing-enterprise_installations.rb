# frozen_string_literal: true

require "monolith_twirp/licensing/enterprise_installations/version"

Dir["#{File.dirname(__FILE__)}/monolith_twirp/**/*_twirp.rb"].each { |file| require file }

module Monolith
  module Twirp
    module Licensing
      module EnterpriseInstallations
        class Error < StandardError; end
      end
    end
  end
end
