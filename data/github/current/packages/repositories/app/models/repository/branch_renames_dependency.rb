# typed: true
# frozen_string_literal: true

module Repository::BranchRenamesDependency
  extend T::Helpers

  requires_ancestor { Repository }

  # Public: Check permission of the given user to rename the specified branch in this repository.
  #
  # actor    - the currently authenticated User or Bot
  # branch   - String branch name to check
  # new_name - optional String proposed new branch name. When provided and the
  #            branch is protected by an org-level or enterprise-level ruleset,
  #            checks that the new name preserves all inherited ruleset coverage.
  #            When nil, returns an optimistic answer suitable for UI display
  #            ("could this actor potentially rename this branch?").
  #
  # Returns a Boolean.
  def branch_renameable_by?(actor, branch:, new_name: nil)
    ref = Git::Ref.new(repository, branch, nil, "refs/heads/")
    ref_renameable_by?(actor, ref: ref, new_name:)
  end

  # Public: Check permission of the given user to rename the specified ref in this repository.
  #
  # actor    - the currently authenticated User or Bot
  # ref      - Git::Ref to check
  # new_name - optional String proposed new branch name (see branch_renameable_by?)
  # switch -   optional Boolean, true if this is a default-branch switch
  #
  # Returns a Boolean.
  sig { params(actor: T.untyped, ref: Git::Ref, new_name: T.nilable(String), switch: T::Boolean).returns(T::Boolean) }
  def ref_renameable_by?(actor, ref:, new_name: nil, switch: false)
    ref_rename_denied_reason(actor, ref:, new_name:, switch:).nil?
  end

  # Public: Determine why a rename is denied, or nil if allowed.
  #
  # actor    - the currently authenticated User or Bot
  # ref      - Git::Ref to check
  # new_name - optional String proposed new branch name. When nil, returns an
  #            optimistic answer suitable for UI display.
  # switch -   optional Boolean, true if this is a default-branch switch. Switches have slighly different behavior becuase
  #            of the ~DEFAULT_BRANCH alias. Both branches must maintain rule coverage before and after the switch.
  #
  # Returns a Symbol reason or nil if the rename is allowed.
  #
  # Possible reasons:
  #   :no_rename_access              - Actor lacks contents-write access
  #   :repo_admin_required           - Actor lacks repo admin to rename default/protected branch
  #   :org_admin_required            - Branch is org-protected, actor is not org admin, relaxed rename is off
  #   :org_rule_coverage_lost        - Relaxed rename is on, but the new name loses org-ruleset coverage
  #   :enterprise_admin_required     - Branch is enterprise-protected, actor is not enterprise admin, relaxed rename is off
  #   :enterprise_rule_coverage_lost - Relaxed rename is on at enterprise level, but new name loses enterprise-ruleset coverage
  sig { params(actor: T.untyped, ref: Git::Ref, new_name: T.nilable(String), switch: T::Boolean).returns(T.nilable(Symbol)) }
  def ref_rename_denied_reason(actor, ref:, new_name: nil, switch: false)
    unless ref.name.b == default_branch.b || ref.protected?
      # This is not the default branch, and it doesn't have any rules. Anyone with write access can rename it
      return non_default_branches_renameable_by?(actor) ? nil : :no_rename_access
    end

    actor_is_repo_admin =
      case actor
      when Botable
        resources.administration.writable_by?(actor)
      else
        adminable_by?(actor)
      end

    # Only enterprise admins can rename a branch, if that branch is restricted by enterprise rules
    if ref.protected_by_business_ruleset?
      # Once we remove the "enforce" feature flag, this code should be tightened up like the org code below
      business =
        if owner && emu_user_owned?
          enterprise_managed_business
        elsif owner.is_a?(Organization)
          owner&.business
        end

      denied_reason = if !business.is_a?(Business)
        :enterprise_admin_required # A business rule is present but we can't find the Business
      else
        actor_is_ent_admin =
          case actor
          when Botable
            business.resources.enterprise_administration.writable_by?(actor)
          else
            business.owner?(actor)
          end

        unless actor_is_ent_admin
          if !business.business_rules_relaxed_rename_enabled?
            :enterprise_admin_required
          else
            if new_name
              if !branch_rename_preserves_rulesets?(actor, ref.name, new_name, switch:) { |r| r.source.is_a?(Business) }
                if actor_is_repo_admin
                  :enterprise_rule_coverage_lost
                else
                  :enterprise_admin_required
                end
              end
            end
          end
        end
      end

      if denied_reason
        enforced = FeatureFlag.vexi.enabled?(:branch_rename_enterprise_rule_protections_enforce, repository, default: false) &&
          !(repository.async_scoped_feature_flag_enabled?(:branch_rename_enterprise_rule_protections_temporary_exempt).sync)

        # If new_name is set, this was an actual attempt to rename the branch, not just "could I rename it?"
        if new_name
          GitHub.logger.info(
            "Attempt to #{switch ? "switch default" : "rename"} branch blocked by enterprise rule",
            "gh.enforced": enforced,
            "gh.relaxed": !!business.try(:business_rules_relaxed_rename_enabled?),
            "gh.actor_is_ent_admin": !!actor_is_ent_admin,
            "gh.actor_is_repo_admin": actor_is_repo_admin,
            "gh.old_name": ref.name,
            "gh.new_name": new_name,
            "gh.repo.id": repository.try(:id),
            "gh.repo.name": repository.try(:name),
            "gh.repo.public": repository.try(:public?) || false,
            "gh.repo.owner.id": repository.try(:owner).try(:id),
            "gh.repo.owner.login": repository.try(:owner).try(:display_login),
          )
        end

        return denied_reason if enforced
      end
    end

    if ref.protected_by_org_ruleset?
      # If this repo is targeted by an org-level rule, the repo must be owned by an Organization
      return :org_admin_required unless (org = owner).is_a?(Organization) # An org rule is present but we can't find the Organization

      actor_is_org_admin =
        case actor
        when Botable
          org.resources.organization_administration.writable_by?(actor)
        else
          org.adminable_by?(actor)
        end

      unless actor_is_org_admin
        # Non org-admin wants to rename an org-protected branch
        return :org_admin_required unless org.org_rules_relaxed_rename_enabled?

        # If no new_name is provided, we're not actually renaming; we're asking if the user might be able to rename.
        # The actual rename would come later, after they propose a new_name.
        if new_name
          if !branch_rename_preserves_rulesets?(actor, ref.name, new_name, switch:) { |r| r.source.is_a?(Organization) }
            if actor_is_repo_admin
              return :org_rule_coverage_lost
            else
              return :org_admin_required
            end
          end
        end
      end
    end

    # It might seem odd that we check this last. But if the proposed rename requires an enterprise or org admin,
    # we don't want to tell a regular user "you need to ask your repo admin" and then when they get a repo admin,
    # tell them "actually, you need an org admin".
    return :repo_admin_required unless actor_is_repo_admin

    nil # no denial reason; rename is permitted
  end

  # Used during a branch rename which targets the default branch. This lets us correctly find the org- and enterprise-
  # level rules which would apply to the renamed default branch.
  attr_reader :renaming_default_branch_to

  # Public: Check whether renaming a branch preserves all ruleset coverage.
  #
  # Every org-level ruleset that applies to the old branch name must also apply to
  # the new name. Additional rulesets covering the new name are acceptable.
  #
  # A ruleset that would otherwise be "lost" by the rename is permitted (treated as preserved) if
  # `actor` is an authorized bypasser on that ruleset. The ids of any such waived rulesets are logged
  # so an investigator can see why a normally-blocked rename was allowed.
  #
  # actor           - User or Bot attempting the rename, used for bypasser checks
  # old_name        - String short branch name (e.g., "main")
  # new_name        - String short branch name (e.g., "trunk")
  # switch          - optional Boolean, true if this is a default-branch switch so we
  #                   verify rules have not been lost on either branch before or after the switch
  #
  # Returns a Boolean.
  sig do
    params(
      actor: T.untyped,
      old_name: String,
      new_name: String,
      switch: T::Boolean,
      filter: T.proc.params(ruleset: RuleEngine::IRuleset).returns(T::Boolean),
    ).returns(T::Boolean)
  end
  def branch_rename_preserves_rulesets?(actor, old_name, new_name, switch: false, &filter)
    old_rulesets = rulesets_for_ref("refs/heads/#{old_name}").select { |r| filter.call(r) }

    return true if old_rulesets.empty?

    if !switch && old_name.b == default_branch.b
      @renaming_default_branch_to = new_name
    end
    new_ruleset_ids = rulesets_for_ref("refs/heads/#{new_name}")
      .filter_map { |r| r.id if filter.call(r) }
      .to_set

    # Rules applying to old_name must be "preserved", ie, apply also to new_name
    preserved_ids = new_ruleset_ids

    if switch
      # Don't let switching the default branch "steal" ruleset coverage by moving DEFAULT_BRANCH. Only consider a
      # rule "preserved" if it (applies to new_name) AND (still applies to old_name with default branch moved away).
      @renaming_default_branch_to = new_name
      old_ruleset_ids_after_change = rulesets_for_ref("refs/heads/#{old_name}")
        .filter_map { |r| r.id if filter.call(r) }
        .to_set

      preserved_ids &= old_ruleset_ids_after_change
    end

    lost = old_rulesets.reject { |r| preserved_ids.include?(T.must(r.id)) }

    if lost.any? && actor
      bypassed = lost.select { |r| r.is_a?(RepositoryRuleset) && r.matches_bypassers?(actor, repository) }
      lost -= bypassed

      if lost.empty? && bypassed.any?
        # Log cases where the operation can succeed (lost is now empty), but would have failed w/o bypass
        GitHub.logger.info(
          "Branch rename ruleset coverage waived for bypasser",
          "gh.switch": switch,
          "gh.old_name": old_name,
          "gh.new_name": new_name,
          "gh.bypassed_ruleset_ids": bypassed.map(&:id),
          "gh.actor_id": actor.try(:id),
          "gh.actor_type": actor.class.name,
          "gh.repo.id": repository.try(:id),
          "gh.repo.owner.login": repository.try(:owner).try(:display_login),
        )
      end
    end

    lost.empty?
  ensure
    @renaming_default_branch_to = nil
  end

  # Public: Get information about the last time the given branch was renamed, if ever.
  #
  # old_name - String name for what the branch used to be called; could be a branch
  #            that no longer exists in this repository; pass if `new_name` is not
  #            specified
  # new_name - String name for what the branch is currently called; pass if `old_name`
  #            is not specified
  #
  # Returns the most recent RepositoryBranchRename record for that branch or nil.
  def branch_rename_for(old_name: nil, new_name: nil)
    renames = branch_renames
    if old_name
      renames = renames.for_old_name(old_name)
    elsif new_name
      renames = renames.for_new_name(new_name)
    end
    renames.finished.latest.first
  end

  # Public: Get branches that are in the process of being renamed.
  #
  # Returns an Array of String branch names.
  def branches_being_renamed
    branch_renames.started.pluck(:old_name)
  end

  # Public: Get branch renames that failed when the rename was attempted recently.
  #
  # Returns a RepositoryBranchRename ActiveRecord::Relation.
  def recently_errored_branch_renames
    branch_renames.errored.since(2.weeks.ago)
  end

  # Public: Is the given branch in the middle of being renamed?
  #
  # branch - String branch name, e.g., "master"
  #
  # Returns a Boolean.
  def branch_being_renamed?(branch)
    branch_renames.where(old_name: branch).started.any?
  end

  # Public: Was the specified branch only given that name within the last two weeks?
  def branch_recently_renamed?(branch)
    branch_renames.for_new_name(branch).finished.since(2.weeks.ago).any?
  end

  private

  # Private: Can the given user rename a non-default branch in this repository?
  def non_default_branches_renameable_by?(actor)
    resources.contents.writable_by?(actor)
  end
end
