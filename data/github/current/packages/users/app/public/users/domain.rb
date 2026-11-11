# typed: strict
# frozen_string_literal: true

module Users
  class Domain < GH::Domain::Base
    SINGLE_ID_QUERY_DIGEST = T.let("e5f5ba142e4ee71571ab064c95e8438f8d464214678741530828a1a2466a4bf8", String)

    accessor Users::Domain::Billing

    # find a user by id
    sig { params(id: T.nilable(Integer)).returns(T.nilable(IUser)) }
    def by_id(id)
      by_single_id(id)
    end

    # find multiple users by id
    sig { params(ids: T::Array[T.nilable(Integer)]).returns(T::Array[IUser]) }
    def by_ids(ids)
      if ids.length == 1
        [by_single_id(ids.first.to_i)].compact
      else
        ::User.where(id: ids.uniq).to_a
      end
    end

    # find a user by
    sig { params(login: String).returns(T.nilable(IUser)) }
    def by_login(login)
      return nil if login.blank?

      ::User.find_by(login:)
    end

    # find multiple users by login
    sig { params(logins: T::Array[String]).returns(T::Array[IUser]) }
    def by_logins(logins)
      return [] if logins.empty?

      ::User.where(login: logins).to_a
    end

    private

    sig { params(id: T.nilable(Integer)).returns(T.nilable(IUser)) }
    def by_single_id(id)
      return nil if id.nil? || id <= 0

      use_cache = ActiveRecord::Base.current_role == :reading && deployment_active?

      if use_cache
        Users::Cache::UserByIdClient.new(id, actor: GH.identity_context.domain_actor).fetch do
          GitHub.context.push(taggable_query_digest: ["digest:#{SINGLE_ID_QUERY_DIGEST}"]) do
            ::User.find_by(id:)
          end
        end
      else
        ::User.find_by(id:)
      end
    end

    sig { returns(T::Boolean) }
    def deployment_active?
      (ENV["USERS_CACHE_CONNECT"] == "1" && FeatureFlag.vexi.enabled?(:users_by_id_cache_interface, default: false)) ||
        (ENV["USERS_CACHE_CONNECT_API"] == "1" && FeatureFlag.vexi.enabled?(:users_cache_api_enabled, default: false)) || (ENV["USERS_CACHE_CONNECT_OTHER"] == "1" && FeatureFlag.vexi.enabled?(:users_cache_other_enabled, default: false))
    end
  end
end
