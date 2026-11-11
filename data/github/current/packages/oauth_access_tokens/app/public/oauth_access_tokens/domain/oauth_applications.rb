# typed: strict
# frozen_string_literal: true

module OauthAccessTokens
  class Domain
    class OauthApplications < GH::Domain::Base
      # Public: Look up OauthApplication IDs based on their keys.
      #
      # key - A String key or an Array of String keys
      #
      # Returns an Array of Integer IDs for OAuth applications matching each of the given keys
      sig { params(keys: T.any(String, T::Array[String])).returns(T::Array[Integer]) }
      def ids_for_keys(keys)
        OauthApplication.where(key: keys).pluck(:id)
      end

      # Public: Returns IDs for GitHub-owned OAuth apps.
      # Results are cached for 1 hour since the set of trusted apps changes very rarely, like a few times per year.
      sig { returns(T::Array[Integer]) }
      def trusted_app_ids
        return [] if GitHub.trusted_apps_owner_id.nil?

        GitHub.cache.fetch("oauth_applications:trusted_app_ids:#{GitHub.trusted_apps_owner_id}",
          expires_in: 1.hour, stats_key: "oauth_applications.trusted_app_ids.cache",
        ) do
          OauthApplication.first_party.pluck(:id)
        end
      end

      # Public: Safely query for an OauthApplication by key
      #
      # key - A String key or an Array of String keys. When multiple keys are
      #       provided, returns the first matching OauthApplication
      #
      # Returns an OauthApplication or nil
      sig { params(key: T.any(String, T::Array[String])).returns(T.nilable(OauthApplication)) }
      def by_key(key)
        OauthApplication.find_by_key(key)
      end

      # Public: Look up an OAuth application by its ID.
      #
      # Returns an OauthApplication or nil.
      sig { params(id: T.nilable(T.any(String, Integer))).returns(T.nilable(OauthApplication)) }
      def by_id(id)
        OauthApplication.find_by(id: id) if id.present?
      end

      # Public: Look up an OAuth application by its ID.
      #
      # Returns an OauthApplication or raises an ActiveRecord::RecordNotFound exception.
      sig { params(id: T.any(String, Integer)).returns(OauthApplication) }
      def by_id!(id)
        OauthApplication.find(id)
      end

      # Public: Look up an OAuth application by its name and the ID of its user.
      #
      # Returns an OauthApplication or nil.
      sig do
        params(user_or_id: T.nilable(T.any(String, Integer, User, Organization)), name: String)
          .returns(T.nilable(OauthApplication))
      end
      def by_user_and_name(user_or_id, name)
        OauthApplication.find_by(user_id: user_or_id, name: name) if user_or_id.present?
      end

      # Public: Check if an OAuth application with the specified ID exists.
      sig { params(id: T.nilable(T.any(Integer, String))).returns(T::Boolean) }
      def exists?(id)
        return false if id.blank?
        OauthApplication.exists?(id)
      end

      class SortOrder < T::Enum
        enums do
          UpdatedAtDescIdDesc = new("oauth_applications.updated_at DESC, oauth_applications.id DESC")
          UpdatedAtDesc = new("oauth_applications.updated_at DESC")
        end
      end

      # Public: Get IDs of OAuth applications that this user owns or can manage because they're owned by an
      # organization the user owns.
      sig { params(user_or_id: T.any(String, Integer, User)).returns(T::Array[Integer]) }
      def adminable_ids(user_or_id)
        OauthApplication.adminable_by(user_or_id).ids
      end

      # Public: Look up OAuth applications that a user owns or can manage because they're owned by an org the
      # user admins.
      #
      # When both `page` and `per_page` are nil (the default), the unpaginated ActiveRecord::Relation is returned so
      # callers like GraphQL connections can apply their own pagination.
      sig do
        params(
          user_or_id: T.nilable(T.any(String, Integer, User)),
          page: T.nilable(Integer),
          per_page: T.nilable(Integer),
          exclude_marketplace: T.nilable(T::Boolean),
          users_to_exclude: T.nilable(T::Array[T.any(Integer, String, User, Organization)]),
          order: T.nilable(SortOrder)
        ).returns(ActiveRecord::Relation)
      end
      def adminable_by(user_or_id, page: nil, per_page: nil, exclude_marketplace: false, users_to_exclude: [], order: nil)
        return OauthApplication.none if user_or_id.blank?

        result = OauthApplication.adminable_by(user_or_id)
        result = result.where.not(user_id: users_to_exclude) if users_to_exclude.present?
        result = result.merge(OauthApplication.not_in_marketplace(result.ids)) if exclude_marketplace
        result = result.order(order.serialize) if order.present?
        return result if page.nil? && per_page.nil?

        result.paginate(page: page || 1, per_page: per_page || 20)
      end
    end
  end
end
