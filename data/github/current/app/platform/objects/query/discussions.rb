# typed: true
# frozen_string_literal: true

module Platform::Objects::Query::Discussions
  extend ActiveSupport::Concern
  extend T::Helpers
  include ::Platform
  include ::GraphQL::Schema::Member::GraphQLTypeNames

  requires_ancestor { Platform::Objects::Query }

  included do
    T.bind(self, T.class_of(Platform::Objects::Query))

    field :discussion_category, Objects::DiscussionCategory, description: "A discussion category from the given repository", null: true, mobile_only: true do
      argument :owner, String, description: "Repository owner", required: true
      argument :repo, String, description: "Repository name", required: true
      argument :slug, String, description: "The slug of the discussion", required: true
    end

    def discussion_category(owner:, repo:, slug:)
      Platform::Helpers::RepositoryByNwo.async_repository_with_owner(
        permission: @context[:permission],
        viewer: @context[:viewer],
        login: owner,
        name: repo,
        follow_repo_redirect: true,
      ).then do |repo|
        if repo
          repo.discussion_categories.where(slug: slug).first
        else
          Promise.resolve(nil)
        end
      end
    end
  end
end
