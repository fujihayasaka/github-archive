# typed: strict
# frozen_string_literal: true

module Admin
  module IBusinessUserAccount
    extend T::Helpers
    abstract!

    sig { abstract.returns(Integer) }
    def id; end

    sig { abstract.returns(T.nilable(Integer)) }
    def user_id; end

    sig { abstract.returns(Integer) }
    def business_id; end

    sig { abstract.returns(T.nilable(String)) }
    def login; end

    sig { abstract.returns(T.nilable(String)) }
    def name; end

    sig { abstract.returns(T.nilable(String)) }
    def display_login; end

    sig { abstract.returns(T.nilable(String)) }
    def verified_emails; end

    sig { abstract.returns(String) }
    def platform_type_name; end

    sig { abstract.returns(T::Boolean) }
    def two_factor_authentication_enabled?; end

    sig { abstract.returns(T.nilable(String)) }
    def ghec_license; end

    sig { abstract.returns(T::Boolean) }
    def has_ghec_license?; end
  end
end
