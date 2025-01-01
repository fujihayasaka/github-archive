# typed: strict
# frozen_string_literal: true

module App
  module IRequestCredentials
    extend T::Sig
    extend T::Helpers

    interface!

    sig { abstract.returns(T.nilable(String)) }
    def login; end

    sig { abstract.returns(T.nilable(String)) }
    def password; end

    sig { abstract.returns(T.nilable(String)) }
    def token; end

    sig { abstract.returns(T.nilable(String)) }
    def otp; end

    sig { abstract.returns(T::Boolean) }
    def login_password_present?; end

    sig { abstract.returns(T::Boolean) }
    def via_params?; end

    sig { abstract.returns(T::Boolean) }
    def proxima_service_token_present?; end
  end
end
