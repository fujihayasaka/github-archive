# typed: true
# frozen_string_literal: true

module SAML
  module Shared
    # Shared behavior for SAML responses. Identical to a Request except that it
    # also has a `InResponseTo` attribute.
    #
    # http://www.datypic.com/sc/saml2/t-samlp_StatusResponseType.html
    module Response
      extend ActiveSupport::Concern

      include Request
      attr_accessor :in_response_to  # String (optional) ID of corresponding Request
      attr_accessor :recipient
      attr_accessor :audience

    end
  end
end
