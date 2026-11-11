# typed: true
# frozen_string_literal: true

module Platform::Objects::Query::Orgs
  extend T::Helpers
  extend ActiveSupport::Concern
  include ::Platform
  include ::GraphQL::Schema::Member::GraphQLTypeNames
  include ::Platform::Objects::Base::EmuChecks

  requires_ancestor { Platform::Objects::Query }

  included do
    T.bind(self, T.class_of(Platform::Objects::Query))

    field :organizations, resolver: Resolvers::Organizations, visibility: { public: { environments: [:enterprise] } }, description: "A list of organizations.", connection: true

    field :organization, Objects::Organization, description: "Lookup a organization by login.", null: true do
      argument :login, String, "The organization's login.", required: true
    end

    def organization(**arguments)
      Loaders::ActiveRecord.load(::User, arguments[:login], column: :login, case_sensitive: false).then do |user|
        if @context[:target] != :internal \
          && user \
          && user.organization?

          user.async_business.then do |business|
            if business&.enterprise_managed_user_enabled? && !can_viewer_access_business(business)
              raise Platform::Errors::NotFound, "Could not resolve to an Organization with the login of '#{arguments[:login]}'."
            elsif user.hide_from_user?(@context[:viewer])
              raise Platform::Errors::NotFound, "Could not resolve to an Organization with the login of '#{arguments[:login]}'."
            end

            user
          end
        elsif user && user.organization? && !user.hide_from_user?(@context[:viewer])
          user
        else
          raise Platform::Errors::NotFound, "Could not resolve to an Organization with the login of '#{arguments[:login]}'."
        end
      end
    end
  end
end
