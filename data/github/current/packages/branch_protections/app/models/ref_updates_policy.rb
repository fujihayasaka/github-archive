# typed: true
# frozen_string_literal: true

# When a Git client pushes to a repository hosted on GitHub, this class
# determines which ref updates are allowed to proceed and which should be
# denied.
class RefUpdatesPolicy
  include UrlHelpers

  # The message when aborting an atomic update.
  ATOMIC_FAILURE_REASON = "atomic transaction failed"

  class Decision
    attr_reader :allowed, :ref_update, :short_message, :long_message

    def initialize(allowed, ref_update, short_message = nil, long_message = nil)
      @allowed = allowed
      @ref_update = ref_update
      @short_message = short_message
      @long_message = long_message
    end

    alias_method :allowed?, :allowed
  end

  # Public: Check the policy for one or more ref updates.
  #
  # repository  - The Repository, Gist, or Unsullied::Wiki whose refs are being updated
  # ref_updates - Array of Git::Ref::Updates
  # actor       - The User, PublicKey, or :slumlord who is performing the update
  #
  # Returns an Array of Decisions, one for each element in ref_updates.
  def self.check(repository, ref_updates, actor, **options)
    new(repository, ref_updates, actor, **options).check
  end

  def initialize(repository, ref_updates, actor, atomic: false, normal_repo: true, sockstat: nil, pre_receive_rule_suites: nil)
    @repository = repository
    @actor = actor
    @ref_updates = ref_updates

    @decisions = {}
    @remaining_updates = ref_updates.index_by(&:refname)

    @atomic = atomic
    @normal_repo = normal_repo

    @default_branch = repository.default_branch if normal_repo?
    @sockstat = sockstat
    @pre_receive_rule_suites = pre_receive_rule_suites
  end

  def check_normal_repo(ref_update)
    case
    when top_level_ref?(ref_update)
      check_top_level_ref_policy(ref_update)
    when invalid_ref?(ref_update)
      check_top_level_ref_policy(ref_update)
    when private_email_ref?(ref_update)
      check_private_email_policy(ref_update)
    when actor == :slumlord
      check_slumlord_policy(ref_update)
    when hidden_ref?(ref_update)
      check_hidden_ref_policy(ref_update)
    when default_branch?(ref_update)
      check_default_branch_policy(ref_update)
    when merge_queue_ref?(ref_update)
      check_merge_queue_ref_policy(ref_update)
    end

    check_branch_rename_policy(ref_update)
  end

  def check
    GitHub.dogstats.distribution_time("repository_rules_engine.ref_updates_policy.duration") do
      remaining_updates.each do |ref_update|
        if normal_repo?
          check_normal_repo(ref_update)
        else
          # https://github.com/github/github/issues/91086
          if private_email_ref?(ref_update)
            check_private_email_policy(ref_update)
          else
            allow_and_ignore_all_other_rules(ref_update)
          end
        end
      end

      check_rules

      final_decisions
    end
  end

  private

  attr_reader :repository, :actor, :default_branch, :normal_repo
  alias :normal_repo? :normal_repo

  # Returns an Array of ref update tuples which have yet to be decided upon.
  def remaining_updates
    @remaining_updates.values
  end

  # Returns an Array of Decisions, one for each item in ref_updates. Do not
  # call this until all decisions have been made.
  def final_decisions
    unless atomic_transaction_failure?
      return @ref_updates.map { |ref_update| @decisions.fetch(ref_update.refname) }
    end

    @ref_updates.map do |ref_update|
      decision = @decisions.fetch(ref_update.refname)

      # If we're already rejecting this for some other reason, report that
      # reason to the user.
      next decision unless decision.allowed?

      # We're rejecting this ref update because it's an atomic transaction and
      # some other ref update has failed.
      Decision.new(false, ref_update, ATOMIC_FAILURE_REASON, nil)
    end
  end

  def atomic_transaction_failure?
    # It's a failure if we're atomic and any ref update will be rejected.
    @atomic && @ref_updates.any? { |ref_update| !@decisions.fetch(ref_update.refname).allowed? }
  end

  # When called, this rule will be allowed, but all rules not yet run will be ignored.
  def allow_and_ignore_all_other_rules(ref_update, display_message = nil)
    record(Decision.new(true, ref_update, nil, display_message))
  end

  def deny(ref_update, short_message, long_message = nil)
    record(Decision.new(false, ref_update, short_message, long_message))
  end

  # Records a Decision.
  #
  # The Decision's ref update is removed from remaining_updates.
  #
  # Returns nothing.
  def record(decision)
    refname = decision.ref_update.refname

    if @decisions.key?(refname)
      fail "Decided #{decision.inspect} but already had decided #{@decisions[refname]}"
    end
    unless @remaining_updates.key?(refname)
      fail "Decided #{decision.inspect} for #{refname} but it wasn't present in remaining_updates"
    end

    @decisions[refname] = decision
    @remaining_updates.delete(refname)
  end

  def top_level_ref?(ref_update)
    !ref_update.refname.start_with?("refs/".freeze)
  end

  def invalid_ref?(ref_update)
    !Rugged::Reference.valid_name?(ref_update.refname)
  end

  HIDDEN_REFS = %w[
    refs/pull
    refs/__gh__
  ].freeze

  HIDDEN_REF_PREFIXES = %w[
    refs/pull/
    refs/__gh__/
  ].freeze

  def hidden_ref?(ref_update)
    HIDDEN_REFS.include?(ref_update.refname) || ref_update.refname.start_with?(*HIDDEN_REF_PREFIXES)
  end

  def merge_queue_ref?(ref_update)
    ref_update.refname.start_with?(MergeQueue::READ_ONLY_REF_PREFIX)
  end

  def check_merge_queue_ref_policy(ref_update)
    deny(ref_update, "refusing to update a read-only ref") if repository.merge_queue_enabled?
  end

  def svn_ref?(ref_update)
    ref_update.refname.start_with?("refs/__gh__/svn/")
  end

  def private_email_ref?(ref_update)
    return false if !actor.try(:warn_private_email?) || !actor.has_primary_email? || actor.primary_user_email.public?
    if ref_update.tag?
      return false if ref_update.deletion?
      ref_emails = [repository.objects.read(ref_update.after_oid).try(:author_email)]
    elsif ref_update.wiki?
      return false if ref_update.deletion?
      commit = repository.commits.find(ref_update.after_oid)
      ref_emails = [commit.try(:author_email), commit.try(:committer_email)]
    elsif ref_update.after_commit
      ref_emails = [ref_update.after_commit.author_email, ref_update.after_commit.committer_email]
    end

    emails = UserEmail.where(email: ref_emails, user_id: actor.id)

    emails.any? &&
    emails.any? do |email|
      (!email.primary_role? || !email.try(:public?)) &&
      !email.to_s.include?("users.noreply")
    end
  end

  def default_branch?(ref_update)
    return false unless default_branch
    ref_update.refname == "refs/heads/#{default_branch}"
  end

  def check_top_level_ref_policy(ref_update)
    deny(ref_update, "funny refname",
         "refusing to create funny ref '#{ref_update.refname}' remotely\n")
  end

  def check_invalid_ref_policy(ref_update)
    deny(ref_update, "funny refname",
         "refusing to create funny ref '#{ref_update.refname}' remotely\n")
  end

  def check_slumlord_policy(ref_update)
    if svn_ref?(ref_update)
      allow_and_ignore_all_other_rules(ref_update)
    else
      deny(ref_update, "non-SVN ref update denied")
    end
  end

  def check_hidden_ref_policy(ref_update)
    deny(ref_update, "deny updating a hidden ref")
  end

  def check_branch_rename_policy(ref_update)
    use_refname_method = GitHub::flipper[:gitauth_branch_rename_policy_refname].enabled?(repository) ||
      (repository.owner.present? && GitHub::flipper[:gitauth_branch_rename_policy_refname].enabled?(repository.owner))

    branch_name = if use_refname_method
      return nil unless ref_update.branch?

      ref_update.unqualified_refname
    else
      ref_update.branch_name
    end

    return unless branch_name

    if repository.branch_being_renamed?(branch_name)
      deny(ref_update, "branch #{branch_name} is being renamed")
    end
  end

  def check_default_branch_policy(ref_update)
    return if ref_update.wiki?
    if ref_update.deletion?
      deny(ref_update, "refusing to delete the current branch: #{ref_update.refname}")
    end
  end

  def check_private_email_policy(ref_update)
    long_message = <<~LONGMESSAGE
      error: GH007: Your push would publish a private email address.
      You can make your email public or disable this protection by visiting:
      #{UrlHelpers.settings_email_preferences_url(host: GitHub.host_name)}
    LONGMESSAGE

    deny(ref_update, "push declined due to email privacy restrictions", long_message)
  end

  def spokes_quarantine?
    @sockstat&.value("spokes_quarantine")
  end

  def check_rules
    return if remaining_updates.empty?
    return unless normal_repo?

    rule_suites = RuleEngine::Evaluator.evaluate_rules(
      repository,
      remaining_updates,
      actor,
      # We will continue to run both phases if Spokes quarantine is not enabled
      phase: if spokes_quarantine?
               RuleEngine::Types::Phase::PostReceive
             else
               nil
             end,
      options: {
        commit_refs_evaluation: true,
        pre_receive_rule_suites: @pre_receive_rule_suites || [],
      }
    )

    rule_suites.each do |rule_suite|
      ref_update = T.must(rule_suite.ref_update)

      if rule_suite.action_permitted?
        if rule_suite.bypassed?
          failure_messages = rule_suite.failure_messages(include_bypassed: true, from_cli: true, exclude_violations: false)

          message = "Bypassed rule violations for #{ref_update.refname}:\n\n#{failure_messages.join("\n\n")}\n\n"
          if rule_suite.additional_cli_message && repository.delegated_bypass_enabled?
            message += T.must(rule_suite.additional_cli_message)
          end
          # This is the last rule in the chain. This is safe because there are no rules after this
          allow_and_ignore_all_other_rules(ref_update, message)
        else
          # This is the last rule in the chain. This is safe because there are no rules after this
          allow_and_ignore_all_other_rules(ref_update)
        end
        next
      end

      if rule_suite.rule_runs.filter(&:failed?).all? { |run| run.rule_type == "workflow_updates" }
        workflow_run = rule_suite.rule_runs.find { |run| run.rule_type == "workflow_updates" }
        deny(ref_update, T.must(workflow_run).message)
      elsif rule_suite.rule_runs.any? { |run| run.failed? && !run.legacy_rule_provider? }
        view_rulesets_url = view_repository_rulesets_url(@repository.owner, @repository, host: GitHub.urls.host_name, ref: ref_update.refname)
        failure_messages = rule_suite.failure_messages(from_cli: true, exclude_violations: false)

        message = "error: GH013: Repository rule violations found for #{ref_update.refname}."
        message += "\nReview all repository rules at #{view_rulesets_url}\n"
        message += "\n#{failure_messages.join("\n\n")}\n\n" if failure_messages.any?
        if rule_suite.additional_cli_message && repository.delegated_bypass_enabled?
          message += "\n#{T.must(rule_suite.additional_cli_message)}"
        end

        deny(ref_update, "push declined due to repository rule violations", message)
      else
        if repository.show_branch_prot_violations_in_cli_feature_enabled?
          long_message = "error: GH006: Protected #{ref_update.ref_type} update failed for #{ref_update.refname}.\n"

          failure_messages = rule_suite.failure_messages(from_cli: true, exclude_violations: false)
          if failure_messages.any?
            long_message += "\n#{failure_messages.join("\n\n")}\n"
          else
            long_message += "error: #{rule_suite.message_without_bypassed_rules}\n"
          end
          if repository.delegated_bypass_enabled?
            long_message += "\n#{T.must(rule_suite.additional_cli_message)}" if rule_suite.additional_cli_message
          end
        else
          long_message = <<~MSG
            error: GH006: Protected #{ref_update.ref_type} update failed for #{ref_update.refname}.
            error: #{rule_suite.message_without_bypassed_rules}
          MSG
          if rule_suite.additional_cli_message && repository.delegated_bypass_enabled?
            long_message += "\n#{T.must(rule_suite.additional_cli_message)}"
          end
        end

        deny(ref_update, "protected #{ref_update.ref_type} hook declined", long_message)
      end
    end
  end
end
