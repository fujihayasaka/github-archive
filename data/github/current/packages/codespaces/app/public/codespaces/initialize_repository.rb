# typed: strict
# frozen_string_literal: true

module Codespaces
  class InitializeRepository < Command
    extend T::Sig

    sig { returns(::Repository) }
    attr_reader :repository
    sig { returns(::User) }
    attr_reader :actor

    sig { params(repository: ::Repository, actor: ::User).void }
    def initialize(repository:, actor:)
      @repository = repository
      @actor = actor
    end

    sig { override.returns(T::Boolean) }
    def perform
      return false unless repository.empty?
      return false unless repository.pushable_by?(actor)

      unless repository.fork?
        # Set the user's preferred default branch even if we're not creating any initial files:
        repository.update_default_branch_spokes("refs/heads/#{default_branch}")
      end

      files = generate_files
      return true if files.empty?

      author = {
        "name" => actor.git_author_name,
        "email" => actor.git_author_email,
        "time" => Time.zone.now.iso8601,
      }

      committer = {
        "email" => GitHub.web_committer_email,
        "name"  => GitHub.web_committer_name,
        "time"  => author["time"],
      }

      info = {
        "message" => "Initial commit",
        "committer" => committer,
        "author" => author,
      }

      args = [nil, info, files]

      commit_oid = repository.rpc.create_tree_changes(*args, &repository.method(:sign_commit))
      repository.heads.build(default_branch).update(commit_oid, actor)

      true
    rescue Git::Ref::RepositoryRuleViolationError, Git::Ref::ProtectedBranchUpdateError
      # TODO: Ideally we'd actually allow these to raise and then handle them in the controller BUT because we're wrapped
      # inside command tracing if this raises it (for some reason) breaks the OTel SDK causing a _different_ error.
      # So, until https://github.com/github/observability/issues/4770 is fixed we have to rescue these and just return
      # false which will at least prevent the 500 but will unfortunately give the user a rather generic error from
      # the controller. Once that bug is fixed though we should remove this rescue and instead rescue it in the controller
      # where we can use e.detailed_message to give the user a more specific error message as to which repository rule
      # was in fact violated.
      false
    end

    sig { returns(String) }
    def default_branch
      repository.owner_default_new_repo_branch
    end

    sig { returns(T::Hash[String, T::Hash[String, String]]) }
    def generate_files
      files = {}

      files["README.md"] = { "data" => generate_readme_content }

      files
    end

    sig { returns(String) }
    def generate_readme_content
      # TODO: Automatically include an "Open in codespace" badge? ;-)
      repository.generate_readme
    end
  end
end
