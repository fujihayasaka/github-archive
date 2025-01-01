# typed: false # rubocop:disable Sorbet/TrueSigil
# frozen_string_literal: true

module Platform::Objects::Query::Lists
  extend ActiveSupport::Concern
  include ::Platform
  include ::GraphQL::Schema::Member::GraphQLTypeNames

  included do
    field :list, Objects::UserList, description: "A user-curated list of repositories with the given slug and belonging to the given user", null: true, required_capabilities: [:mobile_only_schema_mask] do
      argument :login, String, description: "Owner login", required: true
      argument :slug, String, description: "The slug of the list", required: true
    end

    def list(login:, slug:)
      Loaders::ActiveRecord.load(::User, login, column: :login, case_sensitive: false).then do |user|
        user.lists.find_by(slug: slug) if user
      end
    end
  end
end
