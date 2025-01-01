# typed: strict
# frozen_string_literal: true

module AccountSwitcher
  class StashedAccount < T::Struct
    extend T::Sig

    prop :user, User
    prop :user_session_key, String
    prop :user_session, T.nilable(UserSession), default: nil
    prop :valid, T::Boolean, default: false

    sig { returns(T::Boolean) }
    def valid?
      valid
    end

    sig { returns(T::Boolean) }
    def invalid?
      !valid
    end

    sig { params(other: StashedAccount).returns(T::Boolean) }
    def ==(other)
      self.user == other.user &&
      self.user_session_key == other.user_session_key &&
      self.valid == other.valid
      self.user_session == other.user_session
    end
  end
end
