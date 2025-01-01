# typed: strict
# frozen_string_literal: true

class RepositoryOrchestration < ApplicationRecord::Domain::Repositories
  extend T::Sig

  include Orchestration

  sig { returns(T::Hash[Symbol, Integer]) }
  protected def target_uniqueness_condition_on_start
    { repository_id: self.repository_id }
  end

  sig { returns(T.class_of(RepositoryOrchestration)) }
  def self.base_orchestration
    RepositoryOrchestration
  end

  scope :most_recent_for_repository, ->(repository_id) { where(repository_id: repository_id).includes(:repository).order("id DESC") }

  # Gets other running orchestrations targeting the same repository
  sig { returns(T::Array[RepositoryOrchestration]) }
  def concurrent_orchestrations
    GitHub.dogstats.distribution_time("repository_orchestration.concurrent_orchestrations.time") do
      RepositoryOrchestration.where(repository_id: repository_id)
        .where.not(id: id)
        .active
        .to_a
    end
  end

  sig { params(options: T::Hash[String, T.untyped]).returns(T::Hash[String, T.untyped]) }
  def log_data(options = {})
    {
      "code.namespace" => self.class.name,
      "gh.repo.orchestration.id" => id,
      "gh.repo.orchestration.type" => type,
      "gh.repo.orchestration.state" => state,
      "gh.repo.orchestration.step_name" => step_name,
      "gh.repo.orchestration.attempts" => attempts,
      "gh.repo.orchestration.data" => data,
      "gh.repo.id" => repository_id,
      "gh.repo.network_id" => repository&.network_id,
      "gh.actor.id" => data[:actor_id],
      "gh.request_id" => GitHub.context[:request_id],
    }.merge(options)
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def failbot_data
    {
      "gh.repo.id" => repository_id,
      "gh.repo.orchestration.id" => id,
      "gh.repo.orchestration.step_name" => step_name,
      "gh.repo.orchestration.type" => type
    }
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def build_hydro_event_message
    self.class.build_hydro_event_message(repository_id)
  end

  sig { params(repository_id: T.nilable(Integer)).returns(T::Hash[String, T.untyped]) }
  def self.build_hydro_event_message(repository_id)
    message = {
      repository_id: repository_id,
      request_id: GitHub.context[:request_id],
    }
  end

  sig do
    params(
      repository_id: T.nilable(Integer),
      message: T.nilable(T::Hash[String, T.untyped]),
      kwargs: T.untyped
    )
      .returns(Hydro::Sink::Result)
  end
  def self.publish_hydro_event(repository_id:, message: nil, **kwargs)
    # the synchronous event publisher is used to ensure the message is successfully sent before the orchestration
    # continues
    result = GitHub.sync_hydro_publisher.publish(message || build_hydro_event_message(repository_id), **kwargs.merge({ partition_key: repository_id }))
    GitHub.dogstats.increment("orchestration.hydro_publish.status", tags: ["success:#{result.success?}"])
    raise HydroPublishError.new(result.error) unless result.success?
    result
  end

  sig do
    params(
      actor: GH::Auth::Actor,
      owner_login: T.nilable(T.any(User, String)),
      repo_attributes: T::Hash[Symbol, T.untyped],
      reflog_data: T.nilable(T::Hash[Symbol, T.untyped]),
      payment_details: T.nilable(T::Hash[Symbol, T.untyped]),
      role: T.nilable(Symbol),
      skip_validation: T::Boolean,
      custom_properties: T.nilable(T::Hash[Symbol, T.untyped]),
      current_integration_context: T.nilable(T::Hash[Symbol, T.untyped]),
      source_repository: T.nilable(Repository)
    )
      .returns(CreateRepositoryOrchestration)
  end
  def self.create_repository(
    actor:,
    owner_login:,
    repo_attributes:,
    reflog_data: nil,
    payment_details: nil,
    role: nil,
    skip_validation: false,
    custom_properties: nil,
    current_integration_context: nil,
    source_repository: nil
  )
    data = { actor_id: actor.id, source_repository_id: source_repository&.id }.compact_blank

    CreateRepositoryOrchestration.create(
      user: actor,
      repo_params: repo_attributes,
      reflog_data:,
      payment_details:,
      owner_login:,
      role:,
      skip_validation:,
      custom_properties:,
      current_integration_context:,
      data:,
    )
  end

  # factory method to construct a DeleteRepositoryOrchestration
  # repository: The repository to delete
  # deleter: The user who is deleting the repository
  # ignore_forks: If true, leave the child forks untouched. This happens when we already have a set of forks to delete
  # delete_forks_inaccessible_to : the id of a parent repo that all private forks in the network should have access to
  # send_email : send an email that private forks were deleted because their parent was deleted
  # prevent_concurrency: If true, this orchestration will block on other active orchestrations targeting the same repo
  sig do
    params(
      repository: Repository,
      actor: T.nilable(GH::Auth::Actor),
      ignore_forks: T::Boolean,
      delete_forks_inaccessible_to: T.nilable(Integer),
      send_email: T.nilable(T::Boolean),
      prevent_concurrency: T::Boolean,
      staff: T.nilable(T::Boolean)
    )
      .returns(DeleteRepositoryOrchestration)
  end
  def self.delete(
    repository,
    actor:,
    ignore_forks: false,
    delete_forks_inaccessible_to: nil,
    send_email: false,
    prevent_concurrency: false,
    staff: false
  )
    data = {
      deleter_id: actor&.id,
      actor_id: actor&.id,
      ignore_forks:,
      delete_forks_inaccessible_to:,
      send_email:,
      prevent_concurrency:,
      staff:
    }.compact_blank

    o = DeleteRepositoryOrchestration.create(repository: repository, data: data)
    if prevent_concurrency
      o.concurrent_orchestrations.each do |co|
        GitHub.dogstats.increment("repository_orchestration.blocked_on_concurrent", tags: ["type:#{co.type}"])
        o.block_on_orchestration(co)
      end
    end
    o
  end

  sig do
    params(
      repository: Repository,
      new_network_id: T.nilable(Integer),
      reindex: T::Boolean,
      new_extract: T::Boolean,
    )
      .returns(ExtractRepositoryOrchestration)
  end
  def self.extract(repository, new_network_id: nil, reindex: true, new_extract: false)
    data = {
      attach: new_network_id.present?,
      new_network_id:,
      reindex:,
      new_extract:,
    }.compact_blank

    ExtractRepositoryOrchestration.create(repository:, data:)
  end


  sig { params(repository: Repository).returns(DetachRepositoryOrchestration) }
  def self.detach(repository)
    DetachRepositoryOrchestration.create(repository:, data: nil)
  end

  sig do
    params(
      repository: Repository,
      actor: T.nilable(GH::Auth::Actor),
      visibility: String,
    )
      .returns(VisibilityRepositoryOrchestration)
  end
  def self.set_visibility(repository, actor:, visibility:)
    data = {
      actor_id: actor&.id,
      new_visibility: visibility,
    }.compact_blank

    VisibilityRepositoryOrchestration.create(repository:, data:, actor:)
  end

  sig { params(repository: Repository).returns(PurgeRepositoryOrchestration) }
  def self.purge(repository)
    data = {
      owner_id: repository.owner_id,
      network_id: repository.network_id,
      skip_package_destroy_in_repo_purge: repository.owner&.feature_enabled?(:skip_package_destroy_in_repo_purge) || GitHub.flipper[:skip_package_destroy_in_repo_purge].enabled?
    }

    PurgeRepositoryOrchestration.create(repository:, data:)
  end

  sig do
    params(
      repository: Repository,
      actor_id: Integer,
      new_owner_id: Integer,
      team_ids: T::Array[Integer],
      notify_target: T::Boolean,
      new_name: T.nilable(String),
      custom_properties: T.nilable(T::Hash[Symbol, T.untyped])
    )
      .returns(TransferRepositoryOrchestration)
  end
  def self.transfer(
    repository,
    actor_id:,
    new_owner_id:,
    team_ids: [],
    notify_target: false,
    new_name: nil,
    custom_properties: nil
  )
    data = {
      actor_id:,
      new_owner_id:,
      team_ids:,
      notify_target:,
      new_name:,
      custom_properties:,
    }.compact_blank

    TransferRepositoryOrchestration.create(repository:, data:)
  end

  # parent_repository - a Repository that's is going to be forked from
  # forker - The User performing the fork.
  # owner - The User or Organization that will own the fork.
  # name - Name of the forked repository. if nil, an auto-generated name will be used. See Platform::Loaders::NewForkName for details.
  # description - Description of the forked repository. if nil, the description of the parent repository will be used.
  # one_branch - If true, only the default branch of the parent repository will be forked
  sig do
    params(
      parent_repository: Repository,
      actor: GH::Auth::Actor,
      owner: User,
      name: T.nilable(String),
      description: T.nilable(String),
      one_branch: T.nilable(T::Boolean)
    )
      .returns(ForkRepositoryOrchestration)
  end
  def self.fork(
    parent_repository:,
    actor:,
    owner:,
    name: nil,
    description: nil,
    one_branch: false
  )
    data = {
      actor_id: actor.id,
      parent_repository_id: parent_repository.id,
      name: name,
      one_branch: one_branch
    }.compact_blank

    ForkRepositoryOrchestration.create(data:, forker: actor, owner:, parent_repository:, description:)
  end

  sig { returns(T.class_of(TransferRepositoryOrchestration)) }
  def self.transfer_type
    TransferRepositoryOrchestration
  end

  # template_repository - a Repository that's marked as a template
  # actor - the User doing the cloning
  # owner - a User or Organization to own the new repository, cloned from the template repo;
  #         not required if `new_repository` is given
  # new_repository - required if `name` and `owner` are omitted; the new Repository that was
  #                  created that should be populated from the template; if nil, a new repo will be
  #                  created
  # name - the name for the new repository; not required if `new_repository` is given
  # copy_branches - determine if all the branches existing in the template repository should be
  #                 copied into the new repository; defaults to not copying the branches, only
  #                 copying the default branch of the template and its contents to the new repo
  # new_repository_attributes - other attributes for the new repository if `new_repository` wasn't given, can
  #                  include:
  #   public             - True means public, false means private.
  #   visibility         - Used in place of 'public'. Can be public, private, internal.
  #   description        - Optional description as a String.
  #   homepage           - Optional homepage URL as a String.
  #   reflog_data        - Reflog data needed to create initial commit
  #   has_wiki           - Set up wiki for repo
  #   has_downloads      - Set up downloads for repo
  #   has_issues         - Set up issues for repo
  #   team_id            - The team that's granted access to this repository; orgs only
  #   allow_merge_commit - Allow the creation of merge commits - defaults to true
  #   allow_squash_merge - Allow squash merges - defaults to true
  #   allow_rebase_merge - Allow rebase merges - defaults to true
  sig do
    params(
      template_repository: T.nilable(Repository),
      actor: GH::Auth::Actor,
      new_repository: T.nilable(Repository),
      owner: T.nilable(User),
      name: T.nilable(String),
      copy_branches: T.nilable(T::Boolean),
      current_integration_context: T.nilable(T::Hash[Symbol, T.untyped]),
      new_repository_attributes: T.untyped,
    )
      .returns(CloneTemplateOrchestration)
  end
  def self.clone_template(
    template_repository:,
    actor:,
    new_repository: nil,
    owner: nil,
    name: nil,
    copy_branches: false,
    current_integration_context: nil,
    **new_repository_attributes
  )
    data = {
      template_repository_id: template_repository&.id,
      actor_id: actor.id,
      owner_id: owner&.id,
      name: name,
      copy_branches: copy_branches,
    }.compact_blank

    orchestration = CloneTemplateOrchestration.new(data:, actor:, current_integration_context:)

    if new_repository.present?
      orchestration.repository = new_repository
    else
      orchestration.new_repository_attributes = new_repository_attributes
    end

    orchestration.save
    orchestration
  end

  sig do
    params(
      repository: Repository,
      actor: T.nilable(GH::Auth::Actor),
      override_restorable: T::Boolean,
    )
      .returns(RestoreRepositoryOrchestration)
  end
  def self.restore(repository, actor:, override_restorable: false)
    data = {
      actor_id: actor&.id,
      initiated_by: initiated_by,
      override_restorable:,
    }.compact_blank

    RestoreRepositoryOrchestration.create(repository:, data:)
  end

  sig do
    params(
      repository: Repository,
      new_name: String,
      actor: T.nilable(GH::Auth::Actor),
    )
      .returns(RenameRepositoryOrchestration)
  end
  def self.rename(repository, new_name:, actor:)
    data = {
      new_name:,
      actor_id: actor&.id,
      normalized_name: EntityName.normalize(new_name),
      old_name: repository.name.dup,
      old_nwo: repository.name_with_owner.dup, # rubocop:disable GitHub/DoNotAllowNameWithOwner
      was_cname_user_pages_repo: repository.is_cname_user_pages_repo?
    }.compact_blank

    RenameRepositoryOrchestration.create(repository:, data:)
  end

  sig do
    params(
      repository: Repository,
      actor: GH::Auth::Actor,
      old_name: String,
      raw_new_name: T.nilable(String),
      entry_point: Symbol
    )
      .returns(RenameBranchOrchestration)
  end
  def self.rename_branch(repository:, actor:, old_name:, raw_new_name:, entry_point:)
    data = {
      actor_id: actor&.id,
      old_name:,
      raw_new_name:,
      entry_point:,
    }.compact_blank

    RenameBranchOrchestration.create(repository:, data:)
  end

  sig do
    params(
      repository: Repository,
      actor: GH::Auth::Actor,
    )
      .returns(ArchiveRepositoryOrchestration)
  end
  def self.archive(repository, actor:)
    data = {
      actor_id: actor&.id,
    }.compact

    ArchiveRepositoryOrchestration.create(repository:, data:, actor:)
  end

  sig do
    params(
      repository: Repository,
      actor: GH::Auth::Actor,
    )
      .returns(UnarchiveRepositoryOrchestration)
  end
  def self.unarchive(repository, actor:)
    data = {
      actor_id: actor&.id,
    }.compact

    UnarchiveRepositoryOrchestration.create(repository:, data:, actor:)
  end

  sig { returns(String) }
  def self.initiated_by
    GitHub.context[:from].presence || GitHub.context[:job].presence || "unknown"
  end
end
