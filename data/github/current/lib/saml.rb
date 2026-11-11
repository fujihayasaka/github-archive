# typed: true
# frozen_string_literal: true

require "active_support/concern"
require "active_support/core_ext/object/blank"
require "active_support/concern"
require "nokogiri"
require "securerandom"
require "scientist"

# SAML::Shared holds modules for shared behavior. These modules expect to be
# mixed into a SAML::Message subclass.
#
require "saml/shared/issuer"
require "saml/shared/request"
require "saml/shared/response"
require "saml/shared/status"

require "saml/message"
require "saml/message/authn_request"
require "saml/message/assertion"
require "saml/message/logout_request"
require "saml/message/metadata"
require "saml/message/response"

module SAML
  extend self

  # Public: Test helper to mock certain behavior. If `blk` is given, all
  # behavior is guaranteed to be unmocked after `blk` is run.
  #
  # Options
  #  :skip_conditions - Skip validation of conditions for SAML::Message::Response
  #  :skip_validate_signature - Skip validation of xml signature digest for SAML::Message::Response
  #
  def mock(options = {}, &blk)
    self.mocked.merge!(options)
    if blk
      begin
        blk.call
      ensure
        @mocked = @mocked.except(*options.keys)
      end
    end
  end

  # Public: Returns hash of mocked options. See #mock.
  def mocked
    @mocked ||= {}
  end
end
