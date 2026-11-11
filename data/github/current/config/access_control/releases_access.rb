# typed: true
# frozen_string_literal: true

class Api::AccessControl < Egress::AccessControl
  define_access :list_releases do |access|
    access.ensure_context :repo
    access.allow(:everyone) { |context| context[:repo].public? }
    access.allow :repo_contents_reader
  end

  define_access :list_draft_releases do |access|
    access.ensure_context :repo
    access.allow :repo_contents_writer
  end

  define_access :get_release do |access|
    resource_must_belong_to_repo(access)
    access.allow(:everyone)    { |context| context[:repo].public? && context[:resource].published? }
    access.allow(:repo_contents_reader) { |context| context[:resource].published? }
    access.allow :repo_contents_writer
  end

  define_access :create_release do |access|
    access.ensure_context :repo, :user
    access.allow :releases_creator
  end

  define_access :edit_release do |access|
    access.ensure_context :user
    resource_must_belong_to_repo(access)
    access.allow :releases_creator
  end

  # Legacy edit-release access used when `actions_update_release_workflow_scope_check`
  # is disabled. See: https://github.com/github/c2c-actions/issues/10136
  define_access :edit_release_without_workflow_check do |access|
    resource_must_belong_to_repo(access)
    access.allow :repo_contents_writer
  end

  define_access :delete_release do |access|
    resource_must_belong_to_repo(access)
    access.allow :repo_contents_writer
  end
end
