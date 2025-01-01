# typed: true
# frozen_string_literal: true

module Repository::TokenScanningDependency
  extend T::Helpers
  extend ActiveSupport::Concern
  include SecretScanning::Features::FeatureFlagHelper

  requires_ancestor { Repository }

  BATCH_SIZE = 10

  included do
    # TODO Might not need this T.bind() if Repository becomes typed?
    T.bind(self, T.class_of(ApplicationRecord::Base))
    has_one :token_scan_status, dependent: :destroy
    accepts_nested_attributes_for :token_scan_status
    has_many :secret_scan_incremental_statuses
    has_many :secret_scan_custom_patterns
    destroy_dependents_in_background :secret_scan_incremental_statuses
    has_many :token_scan_results
    destroy_dependents_in_background :token_scan_results
  end

  def push_protection_security_center_status
    # prerequisites: token_scanning
    # necessary checks are handled by this feature wrapper
    feature = SecretScanning::Features::Repo::PushProtection.new(self_repo)
    feature_status = feature.enabled?(ignore_import: true) ? "enrolled" : "not_enrolled"
    Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new(feature_status)
  end

  def any_commits_authored_by_user?(actor, commit_oids)
    commit_oids.each do |commit_oid|
      commit = self.find_commit(commit_oid)

      if commit.nil?
        commit = self.find_wiki_commit(commit_oid)
      end

      next if commit.nil?
      if self.feature_flag_enabled?(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::CO_AUTHOR_ALERT_PERMISSIONS, default: true)
        return true if actor.emails.verified.where(email: commit.author_emails).exists? || commit.author_emails.include?(actor.stealth_email_string)
      else
        return true if actor.emails.verified.where(email: commit.author_email).exists? || actor.stealth_email_string == commit.author_email
      end
    end
    false
  end

  sig { params(commit_oid: String).returns(T.nilable(Commit)) }
  def find_commit(commit_oid)
    find_commit_or_tag(self.self_repo, commit_oid)
  end

  sig { params(commit_oid: String).returns(T.nilable(Commit)) }
  def find_wiki_commit(commit_oid)
    wiki = self.unsullied_wiki

    return if wiki.nil?
    return unless wiki.exist?

    find_commit_or_tag(wiki, commit_oid)
  end

  sig { params(actor: Authz::SorbetTypes::Actor).returns(T::Boolean) }
  def can_view_delegated_bypass_requests_list?(actor)
    T.bind(self, ::Repository)
    return false unless self.owner.is_a?(::Organization)
    return false if !actor.is_a?(User)

    return true if self.has_org_delegated_bypass_fgp?(actor)
    return true if self.has_repo_delegated_bypass_fgp?(actor)
    # Repo admins aren't included in the FGP above, but we still want them to be able to view the bypass requests list
    return true if self.adminable_by?(actor)

    actor_user = T.cast(actor, User)
    can_review_bypass_request, _ = SecretScanning::Services::DelegatedBypassService.can_review_bypass_request?(self, actor_user)
    can_review_bypass_request
  end

  sig { params(actor: Authz::SorbetTypes::Actor).returns(T::Boolean) }
  def has_repo_delegated_bypass_fgp?(actor)
    return false if actor.is_a?(ProgrammaticActor)
    self.async_secret_scanning_check_fgp_permissions(actor, :repo_review_and_manage_secret_scanning_bypass_requests).sync
  end

  sig { params(actor: Authz::SorbetTypes::Actor).returns(T::Boolean) }
  def has_org_delegated_bypass_fgp?(actor)
    # This method only makes sense for repos that are owned by orgs
    return false if repository.owner.nil? || !repository.owner.is_a?(Organization)
    return false if actor.is_a?(ProgrammaticActor)
    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :org_review_and_manage_secret_scanning_bypass_requests,
      actor: actor,
      subject: self.owner
    ).then(&:allow?).sync
  end

  def can_view_secret_scanning_alerts?(actor)
    fgp = SecretScanning::AccessControl::FineGrainedPermissions
    fgp.async_batch_check_fgp(actor, :view_secret_scanning_alerts, [self.self_repo]).with_permission.include?(self.id)
  end

  def can_resolve_secret_scanning_alerts?(actor, commit_oids, can_actor_access_as_assignee = false)
    async_secret_scanning_check_fgp_permissions(actor, :resolve_secret_scanning_alerts).sync ||
    vulnerability_manager.adminable_by?(actor) ||
    any_commits_authored_by_user?(actor, commit_oids) ||
    can_actor_access_as_assignee
  end

  def async_secret_scanning_check_fgp_permissions(actor, fine_grain_permission)
    return Promise.resolve(false) unless actor.is_a?(User) && actor.user?

    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: fine_grain_permission,
      actor: actor,
      subject: self
    ).then(&:allow?)
  end

  def secret_scanning_alerts_user_ids
    # This is a temporary solution until https://github.com/github/authorization/issues/2672 is addressed
    user_ids = get_ids_with_secret_scanning_fgps(User.user_role_target_type)

    team_ids = get_ids_with_secret_scanning_fgps(Team.user_role_target_type)
    Team.where(id: team_ids).each { |team| user_ids += team.member_ids }

    user_ids
  end

  def get_ids_with_secret_scanning_fgps(actor_type)
    Role.joins(:permissions, :user_roles).where(
      user_roles: {
        actor_type: actor_type,
        target_id: self.id,
        target_type: user_role_target_type
      },
      permissions: {
        action: [:view_secret_scanning_alerts, :resolve_secret_scanning_alerts]
      }
    ).includes(:user_roles).pluck(:actor_id)
  end

  def config_file
    @token_scanning_yml_file ||= PreferredFile.find(directory: self.root_directory, type: :token_scanning_configuration, subdirectories: [".github"])
  end

  # Get the users to notify of the token scan results found.
  #
  # This returns all users that satisfy the following conditions
  #   - The repo has secret scanning enabled
  #   - The user is authorized to view secret scanning alerts
  #   - The user is subscribed to "security alerts" or "All activity" on the repo
  #   - The user is subscribed to emails under Subcriptions->Watching in their personal notification settings
  #
  # Returns an array of User objects to deliver notifications to
  def token_scanning_users_to_notify
    token_scanning = SecretScanning::Features::Repo::TokenScanning.new(self_repo)
    return [] unless token_scanning.enabled?

    user_ids_to_notify = vulnerability_manager.authorized_user_ids_to_notify |
        SecurityAlert.user_ids_subscribed_to_security_alerts(self, secret_scanning_alerts_user_ids)
    users_to_notify = User.where(id: user_ids_to_notify).to_a
    return users_to_notify unless GitHub.secret_scanning_email_settings_enabled?

    users_to_notify.select do |user|
      can_view = token_scanning.view_alerts_allowed?(user)
      next if !can_view

      next Notifications::Settings.watcher_email?(user)
    end
  end

  # Used for re-evaluating and updating scan state of repos for backfill coverage/cleanup
  # as they transition into eligibility for private token scanning.
  #
  # This method will queue a TokenScanStatus entry when the repo is private AND has token scanning enabled,
  def ensure_backfill_scan_status
    begin
      if SecretScanning::Features::Repo::TokenScanning.new(self_repo).enabled?
        # For a repo, previously marked as non-qualifying, reset any backfill scan
        # information.
        if self.token_scan_status&.scan_state == "non_qualifying_repo"
          self.token_scan_status&.destroy
          if FeatureFlag.vexi.enabled?(:repos_domain_reload, default: false)
            Repositories.domain.reload(T.cast(self, Repository)) # rubocop:todo GitHub/AvoidCast
          else
            self.reload
          end
        end

        TokenScanStatus.ensure_status_entry_for_repo!(self)
      end
    rescue ActiveRecord::ActiveRecordError
      GitHub.dogstats.increment("secret_scanning.backfill_status_ensure_failure")
    end
  end

  # A hydro event is emitted to signal the scan.
  def ensure_backfill_scan_if_enabled(actor:)
    if SecretScanning::Features::Repo::TokenScanning.new(self_repo).enabled?
      # This causes a full backfill to be done, which includes pattern scan, generic secrets,
      # and low-confidence patterns (if they are enabled).
      GlobalInstrumenter.instrument("secret_scanning.backfill.repo", {
        repository: repository,
        actor: actor,
        owner: repository.owner,
        feature_flags: secret_scanning_post_receive_repo_flags,
        type: :START,
        requested_at: Time.now.utc,
        business: {
          id: repository.owner&.business&.id,
          name: repository.owner&.business&.name,
        },
        wiki_scanning: SecretScanning::Features::Repo::WikiScanning.new(self_repo).enabled?,
        is_import: ImportExport.domain.is_importing?(repository)
      })
    end
  end

  # A hydro event is emitted to signal the scan.
  def ensure_generic_secrets_backfill_scan_if_enabled(actor:)
    if SecretScanning::Features::Repo::GenericSecrets.new(self_repo).enabled?
      GlobalInstrumenter.instrument("secret_scanning.generic_secrets_backfill.repo", {
        repository: repository,
        actor: actor,
        owner: repository.owner,
        feature_flags: secret_scanning_post_receive_repo_flags,
        type: :START,
        requested_at: Time.now.utc,
        business: {
          id: repository.owner&.business&.id,
          name: repository.owner&.business&.name,
        },
      })
    end
  end

  # A hydro event is emitted to signal the scan.
  def ensure_low_confidence_backfill_scan_if_enabled(actor:)
    if SecretScanning::Features::Repo::LowerConfidencePatterns.new(self_repo).enabled?
      GlobalInstrumenter.instrument("secret_scanning.low_confidence_backfill.repo", {
        repository: repository,
        actor: actor,
        owner: repository.owner,
        feature_flags: secret_scanning_post_receive_repo_flags,
        type: :START,
        requested_at: Time.now.utc,
        business: {
          id: repository.owner&.business&.id,
          name: repository.owner&.business&.name,
        },
        wiki_scanning: SecretScanning::Features::Repo::WikiScanning.new(self_repo).enabled?,
      })
    end
  end

  sig { params(results_category: Symbol).returns(Integer) }
  def token_scanning_service_load_unresolved_alerts_count_for_result_category(results_category)
    repo = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
      T.cast(Repositories.domain.by_id(id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
    else
      Repository.find_by(id: id)
    end
    return -1 unless repo

    feature_flags = get_tokens_api_feature_flags(repo)
    req = {
      repository_id: id,
      feature_flags: feature_flags,
    }

    count = nil
    case results_category
    when :default
      count = GitHub::TokenScanning::Service::Client.new(@current_user).get_token_counts(req)&.data&.unresolved_count
    when :generic
      req[:low_confidence] = true
      count = GitHub::TokenScanning::Service::Client.new(@current_user).get_token_counts(req)&.data&.unresolved_count
    end
    count || -1
  end

  # count gets the total count of unresolved default and generic alerts
  sig { returns(Integer) }
  def token_scanning_service_unresolved_alerts_count
    generic = token_scanning_service_load_unresolved_alerts_count_for_result_category(:generic)
    return -1 if generic == -1
    default = token_scanning_service_load_unresolved_alerts_count_for_result_category(:default)
    return -1 if default == -1
    generic + default
  end

  def token_scanning_bypass_request_count
    Exemptions::ExemptionRequest.not_expired.where(
      request_type: SecretScanning::Constants::EXEMPTION_REQUEST_TYPE,
      repository_id: repository.id,
      status: "pending"
      # we need to call compute_status because approved requests also have a status = "pending"
    ).to_a.count { |exemption| exemption.compute_status == Exemptions::ExemptionEvaluator::EvaluationResult::Pending }
  end

  def secret_scanning_post_receive_repo_flags
    @secret_scanning_post_receive_repo_flags ||= SecretScanning::Instrumentation::RepositoryServiceFlags.new(self_repo).post_receive_service_flags
  end

  # Public: The preferred TOKEN_SCANNING file from the Repository root.
  #
  # Returns a TreeEntry or nil.
  def preferred_token_scanning
    preferred_file(:token_scanning_configuration)
  end

  def async_preferred_token_scanning
    async_preferred_file(:token_scanning_configuration)
  end

  def security_policy
    @security_policy ||= SecurityPolicy.new(self)
  end

  def preferred_security_policy
    preferred_file(:security)
  end

  sig { returns(Repository) }
  def self_repo
    T.bind(self, Repository)
    self
  end

  # Safely tries to find a commit by:
  # - Checking if commit exists first
  # - Trying to derive commit from a tag if a tag was found
  # - Returning nil if no commit was found
  sig { params(git_repo: T.any(Repository, GitHub::Unsullied::Wiki), commit_oid: String).returns(T.nilable(Commit)) }
  def find_commit_or_tag(git_repo, commit_oid)
    if git_repo.commits.exist?(commit_oid)
      git_repo.commits.find(commit_oid)
    else
      tag = git_repo.read_objects(
        [commit_oid], "tag", true)&.first
      if tag.present? && tag["target_type"] == "commit"
        git_repo.commits.find(tag["target"])
      end
    end
  end
end
