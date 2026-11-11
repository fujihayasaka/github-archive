# typed: true
# frozen_string_literal: true

class GitHubModels::Prompt < ApplicationRecord::Domain::GitHubModels
  self.table_name = "models_prompts"

  extend GitHub::Encoding
  force_utf8_encoding :name, :path, :description, :model

  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain required: true, class_name: "::Repository"

  destroy_in_background_with :repository, sharding_key: :repository_id, sharding_value_key: :id

  validates :path, presence: true

  scope :for_repo, ->(repo_or_id) { where(repository_id: repo_or_id) }
  scope :chronological, -> { order(:created_at) }

  sig { params(repo: T.nilable(Repositories::IRepository)).returns(T.nilable(String)) }
  def self.default_branch_oid_for(repo)
    return unless repo&.respond_to?(:ref_to_sha) && repo.respond_to?(:default_branch)

    ref = T.unsafe(repo).default_branch
    commit_sha = T.unsafe(repo).ref_to_sha(ref)
    return if commit_sha.blank?

    commit = Repositories.domain.commits.by_oid(repository: repo, commit_oid: commit_sha)
    commit&.oid
  end

  sig do
    params(
      repo: Repositories::IRepository,
      path: T.nilable(String),
      oid: T.nilable(String)
    ).returns(T.nilable(TreeEntry))
  end
  def self.blob(repo:, path:, oid: nil)
    return unless repo.respond_to?(:blob)

    oid ||= default_branch_oid_for(repo)
    return if oid.blank?

    T.unsafe(repo).blob(oid, path)
  end

  sig { returns String }
  def to_param
    path
  end

  sig { returns GitHubModels::Types::RepositoryPrompt }
  def to_repo_prompt
    { name: name, description: description, path: path, model: model }
  end
end
