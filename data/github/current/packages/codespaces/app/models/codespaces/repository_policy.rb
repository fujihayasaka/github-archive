# typed: true
# frozen_string_literal: true

module Codespaces
  class RepositoryPolicy
    include GitHub::Memoizer

    attr_reader :user, :repository, :pull_request, :ref

    def self.async_with_prefill(user, repository, pull_request: nil, ref: nil)
      instance = new(user, repository, pull_request: pull_request, ref: ref)
      instance.async_billable_owner.then { instance }
    end

    private def initialize(user, repository, pull_request: nil, ref: nil)
      raise ArgumentError, "`user` cannot be nil" unless user
      raise ArgumentError, "`pull_request` and `ref` are mutually exclusive" if pull_request && ref

      @user = user
      @repository = repository
      @pull_request = pull_request
      @ref = ref || pull_request&.head_ref
    end

    # Determine the billable owner for the repository and user. Note that this
    # assumes the user is authorized to create a codespace from the repository at
    # all.
    # If this returns nil, creating a codespace for this repository is not allowed.
    #
    # See https://github.com/github/codespaces/blob/main/docs/dev/design/billing/billing-ownership-model.md
    def billable_owner
      return @billable_owner if defined?(@billable_owner)

      raise "`billable_owner` should only be called on instances that have been initialized with `#{self.class.name}.async_with_prefill`"
    end

    # Given a repository and user, determine the billable owner. Note that this
    # assumes the user is authorized to create a codespace from the repository at
    # all.
    #
    # See https://github.com/github/codespaces/blob/main/docs/dev/design/billing/billing-ownership-model.md
    def async_billable_owner
      return Promise.resolve(@billable_owner) if defined?(@billable_owner)
      dd_start_time = GitHub::Dogstats.monotonic_time
      dd_stat_name = "codespaces.repository_policy.async_billable_owner"

      span = GitHub.tracer.start_span("codespaces/repository_policy#async_billable_owner")
      # We can't determine a billable owner for a nil repository, bail early
      if @repository.nil?
        async_report_dd_timing(dd_stat_name, dd_start_time)
        span.finish
        @billable_owner = nil
        return Promise.resolve(@billable_owner)
      end

      if org_policy.present?
        # Find out if the user is actually allowed to bill the org (are they a member? etc)
        promise = org_policy.async_can_bill?
      else
        # Default back to billing to the user
        promise = Promise.resolve(false)
      end

      promise.then do |billable_to_org|
        if billable_to_org
          @billable_owner = owning_org
        elsif can_bill_user?
          @billable_owner = @user
        else
          @billable_owner = nil
        end
      ensure
        async_report_dd_timing(dd_stat_name, dd_start_time)
        span.finish
      end
    end

    # Could a codespace be created in this context directly or from forking?
    # Does not take into account behaviors that would block usage such as spamminess,
    # billing limits, payment method issues, etc. For checks that block usage, see Codespaces::AccessChecker.
    def can_attempt_create?(allow_forking: true)
      allowed? && changes_would_be_safe?(allow_forking:)
    end

    # Can the user see codespaces for the current pull request?
    def can_see_codespaces_for_pull_request?
      raise ArgumentError, "cannot check can_see_codespaces_for_pull_request? on a repository policy without a pull request" unless @pull_request

      # If the PR forks the base repo, we only want to allow codespaces if the user can push
      # to that fork because collab is enabled (ie, don't fork a fork, which is convoluted).
      allow_forking = @pull_request.same_repo?
      can_attempt_create?(allow_forking: allow_forking)
    end

    # Can the user start a codespace?
    #
    # This is more lax than #can_attempt_create? which requires that the user be able to
    # push or fork. This just requires that the user be able to read the repo.
    # Does not take into account behaviors that would block usage such as spamminess,
    # billing limits, payment method issues, etc. For checks that block usage, see Codespaces::AccessChecker.
    def can_attempt_start?
      return false unless allowed?

      @repository.readable_by?(@user)
    end

    memoize def read_only_codespace_required?
      return false unless @repository

      !can_push? && can_attempt_start?
    end

    # Could the user bill a codespace created in this context?
    def can_bill?
      billable_owner != nil
    end

    # Can the user modify codespaces repository settings in this context?
    def can_modify_codespace_repo_settings?
      @repository &&
        can_bill? &&
        repository&.owner.codespaces_feature_enabled? &&
        @repository.role_based_access_level(user) == :admin
    end

    # Can the user use Codespaces in any capacity in the context of this
    # repository?
    def allowed?
      return false unless @repository
      return false unless can_bill?
      return false if has_ip_allowlists?
      return false if @repository.advisory_workspace?
      return false if disabled_by_business?
      return false if org_must_upgrade_to_use_codespaces?
      return false if disabled_by_organization?

      true
    end

    def disabled_by_business?
      return false unless @repository
      return false if @repository.public?
      return false unless @repository.owner.is_a?(::Organization)
      return false unless @repository.owner.business.present?

      Codespaces::BusinessDelegator.new(@repository.owner.business).codespaces_disabled_for_org?(@repository.owner)
    end

    def org_must_upgrade_to_use_codespaces?
      owner = billable_owner
      return false unless owner && owner.organization?

      Codespaces::OrgPolicy.new(user: @user, org: owner, repo: @repository).must_upgrade_to_use_codespaces?
    end

    def disabled_by_organization?
      return false unless @repository
      return false if @repository.public?
      return false unless @repository.owner.is_a?(::Organization)

      org_policy.present? ? !org_policy.async_can_use_codespaces?.sync : false
    end

    def changes_would_be_safe?(allow_forking: true)
      if allow_forking
        can_push_or_fork?
      else
        can_push?
      end
    end

    # Until we fully support IP allowlists we have to preven creation of codespaces on repos owned by orgs with IP allowlists enabled
    def has_ip_allowlists?
      return false unless @repository
      # If we're not owned by an org then we don't have IP allowlists
      return false unless @repository.owner&.organization?

      @repository.owner&.ip_allowlist_enabled? || @repository.owner&.ip_allowlist_enabled_on_business? || false
    end

    # Can the user create a fork and reassign this codespace to it?
    memoize def read_only_and_forkable?
      read_only_codespace_required? && can_push_or_fork?
    end

    private

    def can_bill_user?
      if @repository
        repo_owner_has_user_ownership? && !user.is_enterprise_managed?
      else
        !user.is_enterprise_managed?
      end
    end

    def repo_owner_has_user_ownership?
      return true unless @repository
      return true if @repository.public? # only applies to private/internal repos
      return true unless @repository.owner.is_a?(::Organization)

      @repository.owner.codespaces_ownership_set_to_user?
    end

    memoize def can_push?
      return false unless @repository

      @repository.pushable_by?(@user, ref: @ref)
    end

    memoize def can_push_or_fork?
      return false unless @repository

      can_push? || @user.can_fork?(@repository)
    end

    memoize def owning_org
      return unless @repository

      Codespaces::OrgPolicy.owning_organization(@repository)
    end

    memoize def org_policy
      return nil unless owning_org

      Codespaces::OrgPolicy.new(user: @user, org: owning_org, repo: @repository)
    end

    def async_report_dd_timing(stat_name, start_time)
      elapsed = GitHub::Dogstats.duration(start_time)
      GitHub.dogstats.distribution("#{stat_name}.latency", elapsed)
    end
  end
end
