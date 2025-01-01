# typed: strict
# frozen_string_literal: true

module AdvancedSecurity::Features::User
  class AdvancedSecurity
    extend T::Sig

    sig { params(user: User).void }
    def initialize(user)
      @user = user
    end

    sig { returns(T::Boolean) }
    def feature_available?
      business = get_business
      return false if business.nil?

      ::AdvancedSecurity::Features::Business::AdvancedSecurity.new(business).feature_available_for_user_repositories?
    end

    sig { returns(T::Boolean) }
    def security_center_for_emus_enabled?
      business = get_business
      return false if business.nil?

      ::AdvancedSecurity::Features::Business::AdvancedSecurity.new(business).security_center_for_emus_enabled?
    end

    sig { returns(T.nilable(Business)) }
    def get_business
      return GitHub.global_business if GitHub.single_business_environment?

      return nil unless @user.is_enterprise_managed?

      business = @user.enterprise_managed_business
      if business.nil?
        GitHub.logger.info("user is likely being deleted, and while we know they are enterprise managed, we don't know which business they are associated with",
          "gh.user.id": @user.id)
        return nil
      end

      business
    end
  end
end
