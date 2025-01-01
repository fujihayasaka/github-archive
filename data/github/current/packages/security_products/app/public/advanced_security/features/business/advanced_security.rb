# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module AdvancedSecurity::Features::Business
  class AdvancedSecurity
    sig { params(business: Business).void }
    def initialize(business)
      if GitHub.enterprise?
        @delegator = ForGHES.new(business)
      else
        @delegator = ForEMUs.new(business)
      end
    end

    delegate :feature_available_for_user_repositories?, to: :@delegator
    delegate :security_center_for_emus_enabled?, to: :@delegator
    delegate :list_enterprise_users_paged, to: :@delegator
    delegate :list_enterprise_users_offset, to: :@delegator
    delegate :list_enterprise_users_ids_offset, to: :@delegator
    delegate :get_enterprise_users, to: :@delegator
    delegate :num_enterprise_users, to: :@delegator

    class ForGHES
      sig { params(business: Business).void }
      def initialize(business)
        @business = business
      end

      sig { returns(T::Boolean) }
      def feature_available_for_user_repositories?
        return false unless @business.advanced_security_purchased?

        GitHub.ghas_for_enterprise_users_enabled?
      end

      sig { returns(T::Boolean) }
      def security_center_for_emus_enabled?
        return false unless feature_available_for_user_repositories?
        GitHub.security_center_for_emus_enabled?
      end

      sig { params(page: Integer, per_page: Integer).returns(ActiveRecord::Relation) }
      def list_enterprise_users_paged(page:, per_page:)
        return User.none unless feature_available_for_user_repositories?

        User
          .where(type: "User")
          .paginate(page: page, per_page: per_page)
      end

      sig { params(offset_id: Integer, per_page: Integer).returns(ActiveRecord::Relation) }
      def list_enterprise_users_offset(offset_id:, per_page:)
        return User.none unless feature_available_for_user_repositories?

        User
          .where(type: "User")
          .where("id > ?", offset_id)
          .order(:id)
          .limit(per_page)
      end

      sig { params(offset_id: Integer, per_page: Integer).returns(T::Array[Integer]) }
      def list_enterprise_users_ids_offset(offset_id:, per_page:)
        return [] unless feature_available_for_user_repositories?

        User
          .where(type: "User")
          .where("id > ?", offset_id)
          .order(:id)
          .limit(per_page)
          .pluck(:id)
      end

      sig { params(user_ids: T::Array[Integer]).returns(ActiveRecord::Relation) }
      def get_enterprise_users(user_ids:)
        return User.none unless feature_available_for_user_repositories?

        User.where(id: user_ids)
      end

      sig { returns(Integer) }
      def num_enterprise_users
        User
          .where(type: "User")
          .count
      end
    end

    class ForEMUs
      sig { params(business: Business).void }
      def initialize(business)
        @business = business
      end

      sig { returns(T::Boolean) }
      def feature_available_for_user_repositories?
        return false unless @business.advanced_security_purchased?
        return false unless @business.enterprise_managed?
        true
      end

      sig { returns(T::Boolean) }
      def security_center_for_emus_enabled?
        return false unless feature_available_for_user_repositories?

        true
      end

      sig { params(page: Integer, per_page: Integer).returns(ActiveRecord::Relation) }
      def list_enterprise_users_paged(page:, per_page:)
        return User.none unless feature_available_for_user_repositories?
        return User.none unless @business.external_provider_enabled?

        # We could use BusinessUserAccount as well, but ExternalIdentity is a smaller table
        # that is only populated with user accounts from external providers (oidc/saml).
        user_ids = ExternalIdentity
          .by_provider(@business.external_provider)
          .paginate(page: page, per_page: per_page)
          .pluck(:user_id)
        User.where(id: user_ids).order(:id)
      end

      sig { params(offset_id: Integer, per_page: Integer).returns(ActiveRecord::Relation) }
      def list_enterprise_users_offset(offset_id:, per_page:)
        return User.none unless feature_available_for_user_repositories?
        # Guard against new businesses that have not yet set up an external provider.
        return User.none unless @business.external_provider_enabled?

        all_user_ids = ExternalIdentity
          .by_provider(@business.external_provider)
          .where("user_id > ?", offset_id)
          .order(:user_id)
          .limit(per_page)
          .pluck(:user_id)

        User.where(id: all_user_ids).order(:id)
      end

      sig { params(offset_id: Integer, per_page: Integer).returns(T::Array[Integer]) }
      def list_enterprise_users_ids_offset(offset_id:, per_page:)
        return [] unless feature_available_for_user_repositories?
        # Guard against new businesses that have not yet set up an external provider.
        return [] unless @business.external_provider_enabled?

        ExternalIdentity
          .by_provider(@business.external_provider)
          .where("user_id > ?", offset_id)
          .order(:user_id)
          .limit(per_page)
          .pluck(:user_id)
      end

      sig { params(user_ids: T::Array[Integer]).returns(ActiveRecord::Relation) }
      def get_enterprise_users(user_ids:)
        return User.none unless feature_available_for_user_repositories?

        # Guard against new businesses that have not yet set up an external provider.
        return User.none unless @business.external_provider_enabled?

        filtered_user_ids = ExternalIdentity
          .by_provider(@business.external_provider)
          .where(user_id: user_ids)
          .pluck(:user_id)
        User.where(id: filtered_user_ids).order(:id)
      end

      sig { returns(Integer) }
      def num_enterprise_users
        # Guard against new businesses that have not yet set up an external provider.
        return 0 unless @business.external_provider_enabled?

        ExternalIdentity
          .by_provider(@business.external_provider)
          .count
      end
    end
  end
end
