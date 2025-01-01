# typed: true
# frozen_string_literal: true

module Repository::AdvisoryDependency
  extend T::Helpers

  requires_ancestor { Repository }

  extend ActiveSupport::Concern

  included do
    T.bind(self, T.class_of(Repository))

    has_many :repository_advisories do
      def available_to(actor)
        T.bind(self, RepositoryAdvisory::CollectionProxyOrRelationType)

        repo = proxy_association.owner

        # If there is no logged in user and the parent repo is public, we can show
        # published advisories. But if the repo is private, we show nothing.
        unless actor
          # Using Repository#readable_by? rather than Repository#public? takes
          # into account the state of GitHub.private_mode_enabled?.
          return repo.readable_by?(actor) ? published : none
        end

        # If an installation with FGP does not have the repository security advisories scope and the repo is public,
        # we can show published advisories. But if the repo is private, we show nothing.
        if actor.can_have_granular_permissions? && !repo.resources.repository_advisories.readable_by?(actor)
          return repo.readable_by?(actor) ? published : none
        end

        # If the given actor is a repo admin or can manage security products, they can see all of its advisories.
        return all if repo.advisory_viewing_authorized_for?(actor)

        # Otherwise, we're dealing with an actor that may or may not have directly
        # granted abilities on some of the repository's advisories. So we look up
        # which advisory are explicitly available to the actor and combine those
        # with all of the repository's published advisories.
        #
        # This returns *all* advisory IDs granted to this actor.
        all_granted_ids = Authorization.service.subject_ids(
          subject_type: RepositoryAdvisory,
          actor: actor,
          through: [Team],
        )

        if all_granted_ids.any?
          # We need to scope down *all* granted advisories to just those that also
          # belong to the repository.
          published.or(where(id: all_granted_ids))
        else
          # If the actor has not been granted any specific abilities on any
          # advisories, then we return just the published advisories for this
          # repository.
          published
        end
      end

      def state(state)
        T.bind(self, RepositoryAdvisory::CollectionProxyOrRelationType)

        case state
        when :draft
          open_triaged
        when :triage
          open_untriaged
        when :published
          published
        when :closed
          closed
        else
          none
        end
      end

      def limit_advisory_type(type: nil)
        T.bind(self, RepositoryAdvisory::CollectionProxyOrRelationType)

        case type
        when :open_source
          open_source
        when :innersource
          innersource
        else
          proxy_association.owner.innersource_advisories_enabled? ? innersource : open_source.or(where(repo_advisory_type: nil))
        end
      end
    end
    destroy_dependents_in_background :repository_advisories

    has_one :parent_advisory,
      class_name: "RepositoryAdvisory",
      foreign_key: :workspace_repository_id,
      inverse_of: :workspace_repository
  end

  def advisory_workspace?
    return @advisory_workspace if defined?(@advisory_workspace)
    ActiveRecord::Base.connected_to(role: :reading) do
      @advisory_workspace = async_advisory_workspace?.sync
    end
  end

  def async_advisory_workspace?
    async_parent_advisory.then(&:present?)
  end

  def parent_advisory_repository
    async_parent_advisory_repository.sync
  end

  def async_parent_advisory_repository
    async_parent_advisory.then { |advisory| advisory&.async_repository }
  end

  # Determines whether this repo has advisories currently enabled - either innerource advisories or public advisories.
  def advisories_enabled?
    T.bind(self, Repository)

    GitHub.repository_advisories_enabled? &&
      (!AdvisoryDB::Innersource.private_advisory_exempt_repo?(repo: self) || AdvisoryDB::Innersource.repo_authorized?(repo: self))
  end

  # Public: Is Private Vulnerability Reporting enabled for this repository?
  #
  # Returns a Boolean
  sig { returns(T::Boolean) }
  def private_vulnerability_reporting_enabled?
    # Checks if Private vulnerability reporting is enabled for the repository
    T.bind(self, Repository)
    SecurityProduct::PrivateVulnerabilityReporting.new(self).enabled?
  end

  sig { returns(T::Boolean) }
  def innersource_advisories_enabled?
    T.bind(self, Repository)
    SecurityProduct::InnersourceAdvisories.new(self).enabled?
  end

  sig { returns(T::Boolean) }
  def innersource_eligible?
    T.bind(self, Repository)
    AdvisoryDB::Innersource.eligible_repo?(repo: self)
  end

  def add_vulnerability_reporter(addee)
    Permissions::Granters::RoleGranter.new(
      actor: addee, target: self, role: Role.internal_role_by_name("vulnerability_reporter")
    ).grant!
    response = GitHub.newsies.auto_subscribe(addee, self)
    if response.failed?
      GitHub.newsies.async_auto_subscribe(addee, [id])
    end
  end

  def remove_vulnerability_reporter(removee)
    Permissions::Granters::RoleGranter.new(
      actor: removee, target: self, role: Role.internal_role_by_name("vulnerability_reporter")
    ).revoke_if_exists!
    type = self.class.name
    id = self.id
    unless type.nil? || id.nil?
      list = Notifications::Subject.new(type: type, id: id)
      Notifications::Subscriptions.async_delete_user_subscriptions_for_lists(user_id: removee.id, lists: [list])
    end
  end

  # Determines whether an actor is allowed to view un-published advisories for this repo
  def advisory_viewing_authorized_for?(actor)
    return resources.repository_advisories.readable_by?(actor) if actor&.can_have_granular_permissions?
    advisory_management_authorized_for?(actor)
  end

  # Determines whether an actor is allowed to create and edit Advisories for
  # this repo
  def advisory_management_authorized_for?(actor)
    T.bind(self, ::Repository)

    return resources.repository_advisories.writable_by?(actor) if actor&.can_have_granular_permissions?
    return true if SecurityProduct::Permissions::RepoAuthz.new(self, actor:).can_manage_security_products?
    adminable_by?(actor)
  end

  # Ensures that a new workspace has admin abilities that match the source repo
  def setup_workspace_abilities(actor)
    WorkspaceAbilitySetupJob.perform_later(self.id, actor.id)
  end

  # Makes sure that the parent revision is present in the workspace repo
  def fetch_workspace_base_ref!(base_sha:, origin_for_stats: nil)
    return if GitHub.flipper[:disable_xnetwork_fetch].enabled?
    return unless advisory_workspace?
    return if commits.exist?(base_sha) || !parent_advisory_repository.commits.exist?(base_sha)

    stats_tags = ["action:cross_network_fetch"]
    stats_tags << "origin:#{origin_for_stats}" if origin_for_stats.present?

    GitHub.dogstats.time("comparison", tags: stats_tags) do # TODO: should metric be updated to reflect new location?
      rpc.fetch(parent_advisory_repository.internal_remote_url,
        refspec: base_sha,
        no_tags: true,
        no_recurse_submodules: true,
        prune: false,
        quiet: true,
      )
    end
  end

  def hide_repository_advisories_on_delete
    repository_advisories.update_all(owner_id: nil)
  end

  def unhide_repository_advisories_on_restore
    repository_advisories.update_all(owner_id: owner_id)
  end
end
