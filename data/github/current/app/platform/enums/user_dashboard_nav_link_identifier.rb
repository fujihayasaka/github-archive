# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class UserDashboardNavLinkIdentifier < Platform::Enums::Base
      description "An identifier value for a dashboard navigation link."
      mobile_only true

      ::Mobile::HomeNavLink::ALL_LINKS.keys.each do |identifier|
        value identifier.upcase, "'#{identifier}' Link identifier value", value: identifier
      end
    end
  end
end
