# typed: false # rubocop:disable Sorbet/TrueSigil
# frozen_string_literal: true

module Platform::Objects::Query::User
  extend ActiveSupport::Concern
  include ::Platform
  include ::GraphQL::Schema::Member::GraphQLTypeNames
  include ::Platform::Objects::Base::EmuChecks

  included do
    field :account, Platform::Unions::Account, visibility: :internal, description: "Lookup an account by database ID.", null: true do
      argument :account_id, Integer, "The account's database ID.", required: true
    end

    def account(**arguments)
      Loaders::ActiveRecord.load(::User, arguments[:account_id], column: :id).then do |account|
        if account && !account.hide_from_user?(@context[:viewer])
          if account.user? || account.organization?
            account
          end
        end
      end
    end

    field :user, Objects::User, description: "Lookup a user by login.", null: true do
      argument :login, String, "The user's login.", required: true
    end

    def user(**arguments)
      Loaders::ActiveRecord.load(::User, arguments[:login], column: :login, case_sensitive: false).then do |user|

        # Internal calls to lookup EMUs through gql are allowed
        if @context[:target] != :internal  \
          && user&.is_enterprise_managed?

          if !can_viewer_access_business(user.enterprise_managed_business)
            raise Platform::Errors::NotFound, "Could not resolve to a User with the login of '#{arguments[:login]}'."
          end

          user
        end

        if user && !user.hide_from_user?(@context[:viewer]) && user.user?
          user
        else
          raise Platform::Errors::NotFound, "Could not resolve to a User with the login of '#{arguments[:login]}'."
        end
      end
    end

    field :users, resolver: Platform::Resolvers::AllUsers, visibility: { public: { environments: [:enterprise] } }, description: "A list of users.", connection: true

    field :account_from_database_id, Unions::Account, null: true, minimum_accepted_scopes: ["site_admin"] do
      description "Account from database id."
      visibility :internal
      argument :database_id, Int, required: true, description: "The database id of the account."
      argument :enterprise, Boolean, required: false, default_value: false, description: "Whether to search for an Enterprise or not."
    end

    def account_from_database_id(database_id:, enterprise: false)
      account_class = enterprise ? ::Business : ::User
      if Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(context[:viewer], self.class.name)
        Loaders::ActiveRecord.load(account_class, database_id)
      else
        nil
      end
    end

    field :accounts_from_database_ids, [Unions::Account], description: "Accounts from database IDs.", null: false, minimum_accepted_scopes: ["site_admin"] do
      visibility :internal
      argument :database_ids, [Integer], "Account database IDs. Limit 1000.", required: true
    end

    def accounts_from_database_ids(database_ids:)
      if Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(context[:viewer], self.class.name)
        raise Platform::Errors::Validation, "Only up to 1000 IDs is supported." if database_ids.size > 1000

        ::User.where(id: database_ids)
      else
        []
      end
    end

    field :accounts_from_last_ip, Connections.define(Unions::Account), null: true, minimum_accepted_scopes: ["site_admin"] do
      description "Lookup user, organization, and bot accounts from last IP."
      visibility :internal
      argument :ip, String, required: true, description: "IPv4 network address."
      argument :prefix, Enums::NetworkPrefix, required: false, description: Enums::NetworkPrefix.description, default_value: 32
    end

    def accounts_from_last_ip(ip:, prefix: nil)
      if Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(context[:viewer], self.class.name)
        ::User.by_ip_with_prefix(ip, prefix: prefix)
      else
        nil
      end
    end

    field :viewer_has_trade_restrictions, Boolean, required_capabilities: [:mobile_only_schema_mask], description: "Returns true if the user has trade restrictions", null: false

    def viewer_has_trade_restrictions
      return false unless @context[:viewer]
      @context[:viewer].async_trade_controls_restriction.then(&:any?)
    end
  end
end
