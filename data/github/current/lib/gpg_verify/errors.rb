# typed: true
# frozen_string_literal: true

class GpgVerify
  class Error < StandardError
    # The message to show to the user.
    #
    # Returns a String.
    def user_message
      "We got an error adding your GPG key. Please verify the input is a valid GPG key."
    end
  end

  class Unavailable < Error
    # The message to show to the user.
    #
    # Returns a String.
    def user_message
      "Our GPG service is currently offline. Try again later."
    end
  end

  class BadResponse < Error
    # The message to show to the user.
    #
    # Returns a String.
    def user_message
      "We're having trouble talking to your GPG service. Try again later."
    end
  end

  class ServerError < Error
    class << self
      attr_accessor :code, :message_is_user_safe
    end

    # Create a error from a Faraday response.
    #
    # response - A Faraday::Response instance.
    #
    # Returns ServerError subclass instance.
    def self.from_response(response)
      if response.headers["Content-Type"] == Mime[:msgpack]
        data = MessagePack.unpack(response.body)
        klass = subclass_for_code(data["code"])
        klass.new(data["message"])
      else
        new(response.body)
      end
    end

    # Find a ServerError subclass with the given code.
    #
    # code - An integer gpgverify error code.
    #
    # Returns a ServerError subclass.
    def self.subclass_for_code(code)
      subclasses.find { |c| c.code == code } || self
    end

    # Create a new ServerError subclass with the next code.
    #
    # message_is_user_safe: Boolean. Will this error's messages be appropriate to
    #                       return to the user?
    #
    # Returns a ServerError subclass.
    def self.iota(message_is_user_safe: true)
      @iota ||= 0
      klass = Class.new(self)
      klass.code = @iota
      klass.message_is_user_safe = message_is_user_safe
      @iota += 1
      klass
    end

    # The message to show to the user.
    #
    # Returns a String.
    def user_message
      self.class.message_is_user_safe ? message : super
    end
  end

  # From gpgverify's errors.go file.
  UnknownError              = ServerError.iota(message_is_user_safe: false)
  MsgPackError              = ServerError.iota(message_is_user_safe: false)
  OpenPgpError              = ServerError.iota(message_is_user_safe: false)
  BadContentTypeError       = ServerError.iota
  BadBodyError              = ServerError.iota
  NoPgpPacketsError         = ServerError.iota
  MultipleKeysError         = ServerError.iota
  NoPrimaryKeyError         = ServerError.iota
  NoIdentitiesError         = ServerError.iota
  NoUserIdError             = ServerError.iota
  RawPublicKeyDecodeError   = ServerError.iota
  RawSignatureDecodeError   = ServerError.iota
  HashError                 = ServerError.iota
  EarthsmokeError           = ServerError.iota
  RevokedKeyError           = ServerError.iota
  PrivateKeyError           = ServerError.iota
  UnsupportedAlgorithmError = ServerError.iota
end
