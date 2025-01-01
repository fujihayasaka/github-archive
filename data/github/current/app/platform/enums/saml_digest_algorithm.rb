# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SamlDigestAlgorithm < Platform::Enums::Base
      # http://www.datypic.com/sc/ds/e-ds_DigestMethod.html
      description "The possible digest algorithms used to sign SAML requests for an identity provider."

      value "SHA1",   "SHA1",   value: "http://www.w3.org/2000/09/xmldsig#sha1"
      value "SHA256", "SHA256", value: "http://www.w3.org/2001/04/xmlenc#sha256"
      value "SHA384", "SHA384", value: "http://www.w3.org/2001/04/xmlenc#sha384"
      value "SHA512", "SHA512", value: "http://www.w3.org/2001/04/xmlenc#sha512"
    end
  end
end
