# frozen_string_literal: true

require "monolith_twirp/packagefirewall/package_firewall/version"

Dir["#{File.dirname(__FILE__)}/monolith_twirp/**/*_twirp.rb"].each { |file| require file }

module Monolith
  module Twirp
    module Packagefirewall
      module PackageFirewall
        class Error < StandardError; end
      end
    end
  end
end
