# typed: true
# frozen_string_literal: true

class AcmeClient
  class AcmeRequest
    extend T::Helpers
    abstract!
  end

  class NewOrderRequest < AcmeRequest
    attr_reader :identifiers

    sig { params(identifiers: T::Array[String]).void }
    def initialize(identifiers)
      @identifiers = identifiers
    end
  end

  class OrderRequest < AcmeRequest
    attr_reader :url

    sig { params(url: String).void }
    def initialize(url)
      @url = url
    end
  end

  class AuthorizationRequest < AcmeRequest
    attr_reader :url

    sig { params(url: String).void }
    def initialize(url)
      @url = url
    end
  end

  class ClearNoncesRequest < AcmeRequest
    def initialize; end
  end

  attr_reader :key_manager, :attempts, :client

  sig { params(primary_key: T.any(OpenSSL::PKey::RSA, OpenSSL::PKey::EC), directory: String, secondary_key: T.nilable(T.any(OpenSSL::PKey::RSA, OpenSSL::PKey::EC))).void }
  def initialize(primary_key:, directory:, secondary_key: nil)
    @key_manager ||= AcmeKeyManager.new(primary_key, secondary_key)
    @directory = directory
    @client ||= Acme::Client.new(
      private_key: @key_manager.current_key,
      directory: directory
    )
    @attempts = 0
  end

  def make_request(request)
    begin
      case request
      when AuthorizationRequest
        @client.authorization(url: request.url)
      when OrderRequest
        @client.order(url: request.url)
      when NewOrderRequest
        @client.new_order(identifiers: request.identifiers)
      when ClearNoncesRequest
        @client.nonces.clear
      else
        raise "Unknown request type: #{request.class.name}"
      end
    rescue Acme::Client::Error::AccountDoesNotExist => e
      # If this error is thrown, try the other key
      # as long as we haven't already switched the key once
      raise e unless @key_manager.can_switch?

      @client = Acme::Client.new(
        private_key: @key_manager.switch_key,
        directory: @directory
      )
      @attempts += 1
      retry
    ensure
      GitHub.dogstats.increment("acme_client.method", tags: ["method:#{request.class.name}", "key:#{@key_manager.selector}"])
    end
  end

  def authorization(url:)
    request = AuthorizationRequest.new(url)
    make_request(request)
  end

  def new_order(identifiers:)
    return if identifiers.nil? || !identifiers.is_a?(Array)
    request = NewOrderRequest.new(identifiers)
    make_request(request)
  end

  def order(order_url:)
    request = OrderRequest.new(order_url)
    make_request(request)
  end

  def clear_nonces
    request = ClearNoncesRequest.new
    make_request(request)
  end
end

class AcmeKeyManager
  attr_reader :keys, :selector

  sig { params(primary_key: T.any(OpenSSL::PKey::RSA, OpenSSL::PKey::EC), secondary_key: T.nilable(T.any(OpenSSL::PKey::RSA, OpenSSL::PKey::EC))).void }
  def initialize(primary_key, secondary_key)
    @keys = {
      primary: primary_key,
      secondary: secondary_key
    }
    @selector = :primary
    @has_switched = false
  end

  def current_key
    @keys[@selector]
  end

  sig { returns(T.nilable(T.any(OpenSSL::PKey::RSA, OpenSSL::PKey::EC))) }
  def switch_key
    return unless can_switch?

    @selector = @keys[:secondary].present? && @selector == :primary ? :secondary : :primary
    @has_switched = true

    # return the switched key so this can be used to create a new client
    @keys[@selector]
  end

  # if this instance has already switched, that means we've tried both keys
  # and should not switch again
  def can_switch?
    !@has_switched
  end
end
