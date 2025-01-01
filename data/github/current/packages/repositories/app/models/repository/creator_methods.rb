# typed: true
# frozen_string_literal: true

module Repository::CreatorMethods
  include Kernel
  include Repos::GitHubEnterpriseHelper

  sig { params(repo: T::Hash[Symbol, T.untyped]).returns(String) }
  def visibility_from_attributes(repo)
    if repo.key?(:visibility)
      raise ArgumentError, "Invalid attribute value: visibility" unless Repository::VISIBILITIES.include? repo[:visibility]
      # We have to remove this from the hash because it's passed to
      # Repository.new and visibility isn't a proper ActiveRecord
      # attribute.
      return repo.delete(:visibility)
    end
    if owner.organization?
      # It's strange that this validation is only performed for org-owned repos,
      # but changing that caused a dozen test failures, so I'm leaving it.
      raise ArgumentError, "Invalid attribute value: public" unless ["true", "false", true, false].include? repo[:public]
    end
    repo[:public].to_s == "true" ? "public" : "private"
  end

  sig { params(repo: T::Hash[Symbol, T.untyped], repo_visibility: String).returns(T::Boolean) }
  def set_legacy_visibility(repo, repo_visibility)
    repo[:public] = case repo_visibility
    when "private", "internal"
      false
    else
      true
    end
  end

  # Public: Can a given user create a repository
  #
  # visibility - The type of repo to create: "public", "private", or "internal".
  # role       - If the user should be treated as an admin (default: nil).
  #              :admin - To treat the user as an admin.
  #              :octoshift_migrator - To treat the user as a user whos migrating/importing.
  #
  # Retruns a boolean.
  sig { params(repo_visibility: String, role: T.nilable(Symbol)).returns(T::Boolean) }
  def creation_allowed?(repo_visibility, role: nil)
    return false if owner.emu_creating_public_repo?(repo_visibility)

    if owner.organization?
      result = owner.can_create_repository?(@user, visibility: repo_visibility, role: role)
      return result
    end

    true
  end

  sig { params(repository: Repository, actor: User, visibility: String, custom_properties: T.nilable(T::Hash[String, T.untyped])).returns(T::Array[String]) }
  def validate_creation(repository, actor, visibility, custom_properties: nil)
    result = RulesEngine::RepositoryActionEvaluator.validate_creation(repository, @user, visibility, custom_properties:)
    result[:errors]
  end

  def instrument(repository, repo_params)
    tags = ["action:create"]
    tags << "owner:org" if owner.organization?
    tags << "auto_init:true" if repo_params[:auto_init]
    tags << "visibility:#{repository.visibility}"
    tags << "owner_plan:#{owner.plan.name}"

    GitHub.dogstats.increment("repository", tags: tags)
  end

  def owner
    @owner ||= owner!
  end

  def owner!
    if @owner_login.nil?
      raise ArgumentError, "owner can not be nil"
    end

    user = User.find_by_login(@owner_login)
    if user.nil?
      raise ArgumentError, "unknown owner: #{@owner_login.inspect}"
    end

    user
  end

  # https://github.com/github/special-projects/issues/1057
  def creating_repo_in_personal_namespace_for_emu?
    return @creating_repo_in_personal_namespace_for_emu if defined?(@creating_repo_in_personal_namespace_for_emu)
    @user.is_enterprise_managed?
  end

  def creating_repo_in_personal_namespace?
    @user.login == owner.login
  end

  def creating_repo_in_personal_namespace_enterprise_setting_enabled?
    restrict_create_repositories_in_personal_namespace?(@user)
  end

  def creating_repo_in_personal_namespace_enterprise_setting_message
    @user.is_enterprise_managed? ? "Repository creation using enterprise-managed user account inside this enterprise is not allowed." : "Repository creation using user account inside this enterprise is not allowed."
  end

  def is_enterprise_to_restrict_for_personal_namespace?
    GitHub.single_business_environment?
  end

  def check_visibility_and_public(repo)
    raise ArgumentError, "repo cannot have both :public and :visibility" if repo.key?(:visibility) && repo.key?(:public)
  end

  # Part of bug bounty https://github.com/github/search-and-flywheel/issues/98
  # If a user changes their name at the same time a creating a new repo, they could
  # potentially take over a retired namespace unless we lock it during repo creation.
  # If the lock cannot be acquired due to an issue with the database, the repo creation
  # will continue without the lock, leaving us open to the bug bounty, but only during
  # much harder to exploit window.
  def lock_retired_namespace
    return unless owner&.id
    Repositories::RepositoryOwnerLock.acquire_rename_lock(owner_id: owner.id)
  rescue ArgumentError => e
    # if @owner_login is nil or we can't find the user by it, `owner` will
    # raise an ArgumentError. The namespace lock/unlock shouldn't interfere with the
    # orchestration process.
    GitHub.logger.info("Lock for rename failed", {
      "gh.repo.orchestration.owner.login" => @owner_login,
      "exception.type" => "ArgumentError",
      "exception.message" => e.message,
    })
  end

  def unlock_retired_namespace
    return unless owner&.id
    Repositories::RepositoryOwnerLock.release_rename_lock(owner_id: owner.id)
  rescue ArgumentError => e
    # if @owner_login is nil or we can't find the user by it, `owner` will
    # raise an ArgumentError. The namespace lock/unlock shouldn't interfere with the
    # orchestration process.
    GitHub.logger.info("Lock for rename failed", {
      "gh.repo.orchestration.owner.login" => @owner_login,
      "exception.type" => "ArgumentError",
      "exception.message" => e.message,
    })
  end
end
