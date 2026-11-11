# typed: strict
# frozen_string_literal: true

module Admin
  module IBusiness
    extend T::Helpers

    include Kernel
    include FeatureFlag::IFeatureTarget

    abstract!

    # Identity & Display

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    sig { abstract.returns(String) }
    def slug; end

    sig { abstract.returns(String) }
    def name; end

    sig { abstract.returns(T.nilable(String)) }
    def shortcode; end

    sig { abstract.returns(String) }
    def display_login; end

    sig { abstract.returns(String) }
    def safe_profile_name; end

    sig { abstract.returns(T.nilable(ActiveSupport::TimeWithZone)) }
    def created_at; end

    # Plan & Billing State

    sig { abstract.returns(T::Boolean) }
    def trial?; end

    sig { abstract.returns(T::Boolean) }
    def trial_expired?; end

    sig { abstract.returns(T.nilable(T::Boolean)) }
    def metered_plan?; end

    sig { abstract.returns(T::Boolean) }
    def deleted?; end

    # EMU & SSO

    sig { abstract.returns(T::Boolean) }
    def enterprise_managed_user_enabled?; end

    sig { abstract.returns(T::Boolean) }
    def enterprise_managed?; end

    # Authorization

    sig { abstract.params(user: T.nilable(T.any(User, Users::IUser)), include_indirect_abilities: T::Boolean).returns(T::Boolean) }
    def member?(user, include_indirect_abilities: true); end

    sig { abstract.params(user: T.nilable(T.any(User, Users::IUser))).returns(T::Boolean) }
    def owner?(user); end

    sig { abstract.params(user: T.nilable(T.any(User, Users::IUser))).returns(T::Boolean) }
    def billing_manager?(user); end

    # Type Discrimination

    sig { abstract.returns(T::Boolean) }
    def business?; end
  end
end
