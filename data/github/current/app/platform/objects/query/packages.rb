# typed: false # rubocop:disable Sorbet/TrueSigil
# frozen_string_literal: true

module Platform::Objects::Query::Packages
  extend ActiveSupport::Concern
  include ::Platform
  include ::GraphQL::Schema::Member::GraphQLTypeNames

  included do
    field :package_owner, Interfaces::PackageOwner, visibility: :internal, description: "Lookup a registry package owner", null: true do
      argument :login, String, "The name to lookup the owner by.", required: true
    end

    def package_owner(**arguments)
      Loaders::ActiveRecord.load(::User, arguments[:login], column: :login, case_sensitive: false).then do |user|
        next unless user
        @context[:permission].typed_can_see?("User", user).then do |owner_readable|
          if owner_readable && !user.hide_from_user?(@context[:viewer])
            user
          else
            nil
          end
        end
      end
    end

    field :package_search, Interfaces::PackageSearch, visibility: :internal, description: "Search packages under a registry package owner", null: true do
      argument :login, String, "The name to lookup the owner by.", required: true
    end

    def package_search(**arguments)
      Loaders::ActiveRecord.load(::User, arguments[:login], column: :login, case_sensitive: false).then do |user|
        next unless user
        @context[:permission].typed_can_see?("User", user).then do |owner_readable|
          if owner_readable && !user.hide_from_user?(@context[:viewer])
            user
          else
            nil
          end
        end
      end
    end
  end
end
