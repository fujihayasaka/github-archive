# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EmailDomainAddressType < Platform::Enums::Base
      description "Email domain address type."
      visibility :internal

      value "EMAIL_DOMAIN", "Email address domain name.", value: :email_domain
      value "MX_EXCHANGE", "MX exchange.", value: :mx_exchange
      value "A_RECORD", "A record.", value: :a_record
    end
  end
end
