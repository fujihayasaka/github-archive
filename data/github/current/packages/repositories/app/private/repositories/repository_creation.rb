# typed: strict
# frozen_string_literal: true

module Repositories
  # NOTE: keep this in sync with packages/repositories/app/models/repository/creatable.rb while that
  # path is being replaced with the domain instead.
  class RepositoryCreation
    sig do
      params(repo_attributes: CreateRepositoryAttributes, integration_context: T.untyped, actor: GH::Auth::Actor).
      void
    end
    def initialize(repo_attributes:, integration_context:, actor:)
      @repo_attributes = repo_attributes
      @integration_context = integration_context
      @actor = actor
    end

    sig { returns(CreateRepositoryAttributes) }
    attr_reader :repo_attributes

    sig { returns(T.untyped) }
    attr_reader :integration_context

    sig { returns(GH::Auth::Actor) }
    attr_reader :actor

    sig { returns(GH::Result[IRepository]) }
    def execute
      if T.cast(owner, User).user? && owner != actor
        return GH::Result::Error::AccessDenied.new(permission_message)
      end

      if !GitHub.public_repositories_available? && repo_attributes.visibility == RepositoryVisibility::Public
        return GH::Result::Error::AccessDenied.new("Public repositories not permitted on #{GitHub.flavor}")
      end

      # TODO: this needs to be reconciled with https://github.com/github/github/blob/e0e3131d86d7e600577021b96c529321ea695c8e/packages/repositories/app/models/repository/creator_methods.rb#L41 which does the same check in the orchestration but without the user visible error message.
      if T.cast(actor, User).emu_creating_public_repo?(repo_attributes.visibility.serialize)
        return GH::Result::Error::AccessDenied.new("Public repositories are not permitted for Enterprise Managed Users.")
      end

      o = create_orchestration

      if o.allowed == false
        message = o.errors[:repository].first
        # In many places in the orchestration we simply mark the orchestration as "invalid" and set allowed to false.
        # But in others, we set allowed to false but also set a useful message! So we need to check for that.
        # See https://github.com/github/repos/issues/11243
        message = message == "is invalid" ? permission_message : message
        return GH::Result::Error::AccessDenied.new(message)
      end
      return GH::Result::Error::Validation.new(o.built_repository, message: o.error_message || o.errors[:repository].first) if o.errors.any?

      o.execute(synchronous: false)

      if o.failed?
        # If we fail before saving the repo, then o.repository will be nil, so get content from o.built_repository
        repo = o.built_repository || o.repository

        return GH::Result::Error::AccessDenied.new(permission_message) if o.allowed == false
        return GH::Result::Error::Validation.new(repo, message: o.error_message || o.errors[:repository].first) if o.errors.any?
        return GH::Result::Error.new(o.error_message)
      elsif o.skipped?
        return GH::Result::Error::Validation.new(o.built_repository, message: o.error_message || o.errors[:repository].first)
      end

      GH::Result::Ok.new(T.must(o.repository))
    end

    private

    sig { returns(CreateRepositoryOrchestration) }
    def create_orchestration
      reflog_data = repo_attributes.reflog_data

      reflog_data ||= {
        repo_name: "#{owner.login}/#{repo_attributes.name}", # rubocop:disable GitHub/DoNotAllowLogin
        repo_public: repo_attributes.visibility == RepositoryVisibility::Public,
      }

      attrs = repo_attributes.to_hash
      attrs.delete(:owner)
      attrs.delete(:reflog_data)

      attrs[:owner_login] = owner.login # rubocop:disable GitHub/DoNotAllowLogin

      # upcase for now to match currently expected strings
      safe_upcase(attrs, :squash_merge_commit_message)
      safe_upcase(attrs, :squash_merge_commit_title)
      safe_upcase(attrs, :merge_commit_message)
      safe_upcase(attrs, :merge_commit_title)

      orchestration = RepositoryOrchestration.create_repository(
        actor:,
        owner_login: T.must(owner.login), # rubocop:disable GitHub/DoNotAllowLogin
        repo_attributes: attrs,
        reflog_data:,
        current_integration_context: integration_context
      )

      GitHub.dogstats.increment("repository", tags: ["action:create", "valid:false"]) if orchestration.errors.any?

      orchestration
    end

    sig { returns(Users::IUser) }
    def owner
      return T.must(@owner) if defined?(@owner)

      owner = T.let(repo_attributes.owner, T.nilable(T.any(String, Users::IUser)))

      # This is explicitly assuming the actor is some type of user. We currently already implicitly assume it
      # so this should be better than the status quo as it at least will fail noisily if the assumption
      # proves wrong.
      owner = T.cast(actor, Users::IUser) if owner.nil?
      owner = T.must(Users.domain.by_login(owner)) if owner.is_a?(String)

      @owner = T.let(owner, T.nilable(Users::IUser))
      T.must(@owner)
    end

    sig { returns(String) }
    def permission_message
      "#{actor.display_login} cannot create a repository for #{owner.display_login}."
    end

    sig { params(attrs: T::Hash[Symbol, T.untyped], property: Symbol).void }
    def safe_upcase(attrs, property)
      value = attrs[property]
      return if value.nil?

      attrs[property] = value.upcase
    end
  end
end
