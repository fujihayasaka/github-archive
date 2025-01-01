# typed: strict
# frozen_string_literal: true

module Orgs
  module IOrganization
    extend T::Helpers

    include Kernel
    include Substrate::IRepositoryOwner
    include FeatureFlag::IFeatureTarget

    abstract!

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    sig { abstract.returns(T::Boolean) }
    def organization?; end

    sig { abstract.returns(T.nilable(Admin::IBusiness)) }
    def business; end

    sig { abstract.returns(Promise[T.nilable(Admin::IBusiness)]) }
    def async_business; end

    sig { abstract.returns(T::Boolean) }
    def active?; end

    sig { abstract.returns(Organization::Resources) }
    def resources; end

    sig { abstract.params(user: T.nilable(T.any(User, Users::IUser))).returns(T::Boolean) }
    def member?(user); end

    sig { abstract.params(id: T.nilable(T.any(User, Integer)), repository_ids: T::Array[T.nilable(Integer)]).returns(T::Boolean) }
    def user_is_outside_collaborator?(id, repository_ids = []); end

    sig { abstract.params(user: T.nilable(T.any(User, Users::IUser))).returns(T::Boolean) }
    def adminable_by?(user); end

    sig { abstract.returns(String) }
    def safe_profile_name; end

    sig { abstract.returns(String) }
    def display_login; end
  end
end
