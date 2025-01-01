# typed: true
# frozen_string_literal: true

class Faraday::Env < ::Faraday::Options

  sig do
    params(
      method: T.nilable(String),
      body: T.untyped,
      url: T.untyped,
      request: T.nilable(Faraday::RequestOptions),
      request_headers: T.untyped,
      ssl: T.untyped,
      parallel_manager: T.untyped,
      params: T.untyped,
      response: T.untyped,
      response_headers: T.untyped,
      status: T.nilable(Integer),
      reason_phrase: T.nilable(String)
    ).returns(T.self_type)
  end
  def self.new(
    method: nil,
    body: nil,
    url: nil,
    request: nil,
    request_headers: nil,
    ssl: nil,
    parallel_manager: nil,
    params: nil,
    response: nil,
    response_headers: nil,
    status: nil,
    reason_phrase: nil
  ); end

  sig { returns(T.nilable(String)) }
  def method; end

  sig { returns(T.nilable(Integer)) }
  def status; end

  sig { returns(URI::HTTP) }
  def url; end

  sig { returns(T.nilable(Faraday::RequestOptions)) }
  def request; end
end

class Faraday::Adapter
  sig { params(type: Symbol, options: ::Faraday::Options).returns(T.nilable(Integer)) }
  def request_timeout(type, options); end
end

class Faraday::RequestOptions
  sig do
    params(
      params_encoder: T.untyped,
      proxy: T.untyped,
      bind: T.untyped,
      open_timeout: T.untyped,
      read_timeout: T.untyped,
      write_timeout: T.untyped,
      timeout: T.untyped,
      boundary: T.untyped,
      oauth: T.untyped,
      context: T.nilable(T::Hash[T.untyped, T.untyped]),
      on_data: T.untyped
    ).returns(T.attached_class)
  end
  def self.new(
    params_encoder: nil,
    proxy: nil,
    bind: nil,
    open_timeout: nil,
    read_timeout: nil,
    write_timeout: nil,
    timeout: nil,
    boundary: nil,
    oauth: nil,
    context: nil,
    on_data: nil
  ); end

  sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
  def context; end
end
