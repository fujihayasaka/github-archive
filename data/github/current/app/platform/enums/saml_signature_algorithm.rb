# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SamlSignatureAlgorithm < Platform::Enums::Base
      # http://www.datypic.com/sc/ds/e-ds_SignatureMethod.html
      description "The possible signature algorithms used to sign SAML requests for a Identity Provider."

      value "RSA_SHA1",   "RSA-SHA1",   value: "http://www.w3.org/2001/04/xmldsig-more#rsa-sha1"
      value "RSA_SHA256", "RSA-SHA256", value: "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"
      value "RSA_SHA384", "RSA-SHA384", value: "http://www.w3.org/2001/04/xmldsig-more#rsa-sha384"
      value "RSA_SHA512", "RSA-SHA512", value: "http://www.w3.org/2001/04/xmldsig-more#rsa-sha512"
    end
  end
end
