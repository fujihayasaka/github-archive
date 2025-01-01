# typed: strict
# frozen_string_literal: true

module ServerToServerTokens
  module IAuthenticationToken
    extend T::Helpers

    include Kernel

    abstract!

    sig { abstract.returns(Integer) }
    def id; end

    sig { abstract.returns(Integer) }
    def authenticatable_id; end

    sig { abstract.returns(String) }
    def authenticatable_type; end

    sig { returns(T.class_of(ApplicationRecord::Base)) }
    def authenticatable_class
      authenticatable_type.constantize
    end

    sig { abstract.returns(String) }
    def hashed_value; end

    sig { abstract.returns(String) }
    def token_last_eight; end

    sig { abstract.returns(T.nilable(Time)) }
    def created_at; end

    sig { abstract.returns(T.nilable(Time)) }
    def expires_at_timestamp; end

    sig { abstract.returns(T::Boolean) }
    def expired?; end

    sig { abstract.returns(T.nilable(Time)) }
    def valid_after; end

    sig { abstract.params(time: T.nilable(Time)).void }
    def valid_after=(time); end
  end
end
