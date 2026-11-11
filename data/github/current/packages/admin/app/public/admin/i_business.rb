# typed: strict
# frozen_string_literal: true

module Admin
  module IBusiness
    extend T::Helpers

    include Kernel
    include FeatureFlag::IFeatureTarget

    abstract!

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    sig { abstract.returns(String) }
    def slug; end

    sig { abstract.returns(String) }
    def safe_profile_name; end

    sig { abstract.params(user: T.nilable(T.any(User, Users::IUser)), include_indirect_abilities: T::Boolean).returns(T::Boolean) }
    def member?(user, include_indirect_abilities: true); end
  end
end
