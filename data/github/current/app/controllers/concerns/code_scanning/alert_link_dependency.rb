# typed: strict
# frozen_string_literal: true

module CodeScanning
  module AlertLinkDependency
    extend ActiveSupport::Concern
    extend T::Helpers

    include UrlHelper

    requires_ancestor { ApplicationController }

    sig { params(pull_request: PullRequest, repository: Repository).returns(T::Hash[Symbol, T.untyped]) }
    def convert_to_pull_request_picker_props(pull_request, repository)
      {
        type: "pull_request",
        baseRefName: pull_request.base_ref_name,
        baseRefUrl: tree_path("", pull_request.base_ref_name, repository),
        closedAt: pull_request.closed_at,
        createdAt: pull_request.created_at,
        isDraft: pull_request.draft?,
        mergedAt: pull_request.merged_at,
        number: pull_request.number,
        state: "#{pull_request.state}".upcase,
        title: pull_request.title,
        url: pull_request.url
      }
    end

    sig { params(branch: Git::Ref, repository: Repository).returns(T::Hash[Symbol, T.untyped]) }
    def convert_to_branch_picker_props(branch, repository)
      {
        type: "branch",
        name: branch.name,
        url: tree_path("", branch.name, repository),
        lastModifiedAt: branch.last_modified_at,
      }
    end

    sig { params(repository: Repository).returns(T::Hash[Symbol, T.untyped]) }
    def repository_props(repository)
      {
        id: repository.id,
        nameWithOwner: repository.name_with_display_owner,
      }
    end
  end
end
