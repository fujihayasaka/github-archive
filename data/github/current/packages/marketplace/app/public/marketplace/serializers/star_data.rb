# typed: strict
# frozen_string_literal: true

module Marketplace
  module Serializers
    class StarData
      include T::Helpers
      include EnterpriseManagedUsersHelper

      sig { returns(T::Boolean) }
      attr_reader :logged_in

      sig { returns(T.nilable(User)) }
      attr_reader :current_user

      sig { returns(::Repository) }
      attr_reader :repository

      sig { returns(T::Boolean) }
      attr_reader :emu_contribution_blocked

      sig do
        params(
          logged_in: T::Boolean,
          current_user: T.nilable(User),
          repository: ::Repository,
          emu_contribution_blocked: T::Boolean
        ).void
      end
      def initialize(logged_in:, current_user:, repository:, emu_contribution_blocked:)
        @logged_in = logged_in
        @current_user = current_user
        @repository = repository
        @emu_contribution_blocked = emu_contribution_blocked
      end

      alias :logged_in? :logged_in
      alias :emu_contribution_blocked? :emu_contribution_blocked

      sig { returns(Marketplace::Types::SerializedStarData) }
      def call
        {
          starredByCurrentUser: starred_by_user?,
          currentUserAbleToStar: user_can_star?,
          currentUserEnterpriseName: enterprise_name
        }
      end

      private

      sig { returns(T::Boolean) }
      def user_can_star?
        return false unless logged_in? && current_user.present?
        return false if T.must(current_user).is_enterprise_managed? && emu_contribution_blocked?

        true
      end

      sig { returns(T::Boolean) }
      def starred_by_user?
        return false unless logged_in? && current_user.present?

        Stars.domain.repo_starred_by_user?(repository.id, T.must(current_user).id)
      end
    end
  end
end
