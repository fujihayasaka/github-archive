# typed: true
# frozen_string_literal: true

module Discussions
  module Settings
    class OrgLevelRepoSelectComponent < ApplicationComponent
      def initialize(organization:, repos_path:)
        @organization = organization
        @discussion_repo = organization.discussion_repository
        @has_discussion_repo = @discussion_repo.present?
        @repos_path = repos_path
      end
    end
  end
end
