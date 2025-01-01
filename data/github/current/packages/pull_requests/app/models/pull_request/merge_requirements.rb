# typed: true
# frozen_string_literal: true

class PullRequest::MergeRequirements
  include GitHub::Memoizer

  attr_reader :pull_request, :viewer, :skip_checks

  def initialize(pull_request, merge_action, merge_method, bypass_requirements, viewer, skip_checks: false)
    @pull_request = pull_request
    @merge_action = merge_action
    @merge_method = merge_method
    @bypass_requirements = bypass_requirements
    @viewer = viewer
    @skip_checks = skip_checks
  end

  sig { returns(T.nilable(String)) }
  def default_commit_author_email
    async_default_commit_author_email.sync
  end

  def async_default_commit_author_email
    merge_method.then do |selected_merge_method|
      case selected_merge_method
      when :merge
        pull_request.merge_commit_author_email(viewer)
      when :squash
        pull_request.squash_commit_author_email(viewer)
      when :rebase
        nil
      else
        nil
      end
    end
  end

  sig { returns(T::Array[String]) }
  def possible_commit_author_emails
    async_possible_commit_author_emails.sync
  end

  def async_possible_commit_author_emails
    merge_method.then do |selected_merge_method|
      case selected_merge_method
      when :merge
        viewer.author_emails
      when :squash
        viewer == pull_request.user ? viewer.author_emails : []
      when :rebase
        []
      else
        []
      end
    end
  end

  def state
    async_state.sync
  end

  def async_state
    Promise.all([
      @pull_request.async_repository,
      @pull_request.async_base_repository,
      @pull_request.async_head_repository,
      @pull_request.async_merge_queue,
    ]).then do |result|
      merge_queue = result.pop
      repositories = result

      if merge_queue
        GitHub::PrefillAssociations.prefill_associations(merge_queue, :repository, available_records: repositories)
      end

      networks = repositories.compact.map(&:async_network)
      users = [@pull_request.async_base_user, @pull_request.async_head_user, @pull_request.async_user]

      Promise.all(networks + users).then do
        @pull_request.enqueue_mergeable_update(priority: :high)

        next :unknown if @pull_request.currently_mergeable?.nil?

        async_conditions.then do |conditions|
          has_failing_conditions = conditions.any? { |c| c.result == :failed }
          if has_failing_conditions
            :unmergeable
          elsif @skip_checks
            async_has_required_checks.then do |has_required_checks|
              if has_required_checks
                :mergeable_if_statuses_pass
              else
                :mergeable
              end
            end
          else
            :mergeable
          end
        end
      end
    end
  end

  sig { returns(Promise[T::Boolean]) }
  def async_has_required_checks
    @pull_request.async_batch_base_branch_rule_evaluator.then do |rule_evaluator|
      rule_evaluator &&
        rule_evaluator.required_status_checks_enabled? &&
        rule_evaluator.required_status_checks.any?
    end
  end

  sig { returns(T::Array[MergeConditions::BaseMergeCondition]) }
  def conditions
    async_conditions.sync
  end

  sig { returns(Promise[T::Array[MergeConditions::BaseMergeCondition]]) }
  memoize def async_conditions
    merge_method.then do |selected_merge_method|
      ::MergeConditions::Evaluator.async_evaluate(pull_request, viewer, selected_merge_method, skip_checks: skip_checks)
    end
  end

  # The merge action being used to evaluate mergeability. See async_evaluated_merge_action
  def merge_action
    async_evaluated_merge_action.then do |action|
      action.name
    end
  end

  # The AllowableMergeAction being used to evaluate mergeability. It was either determined by an argument or the first allowable action for the user.
  memoize def async_evaluated_merge_action
    Promise.all([::PullRequest::AllowableMergeAction.for(pull_request: pull_request, viewer: viewer), pull_request.async_merge_queue_enabled?]).then do |(actions, merge_queue_enabled)|
      action = if @merge_action
        # If an action was specified, use it even if it's not allowed
        actions.find { |a| a.name == @merge_action }
      elsif @bypass_requirements
        # If no action was specified, but bypass was requested, use the first allowable action that can be bypassed
        actions.find { _1.allowable_status == :allowed_with_bypass } || actions.find { _1.allowable_status == :allowed }
      else
        # if no action or bypass was specified, use the first allowable action
        actions.find { _1.allowable_status == :allowed }
      end

      # If we reached this point, fallback to the action that is available
      if action.present?
        action
      else
        merge_queue_enabled ? actions.find { |action| action.name == :merge_queue } : actions.find { |action| action.name == :direct_merge }
      end
    end
  end

  # The merge method being used to evaluate mergeability. See async_evaluated_merge_method
  def merge_method
    async_evaluated_merge_method.then do |method|
      method.name
    end
  end

  memoize def async_evaluated_merge_method
    async_evaluated_merge_action.then do |action|
      action.merge_methods.then do |methods|
        if @merge_method && action.name != :merge_queue
          methods.detect do |method|
            # Some callers will pass @merge_method as a string and others will pass it a symbol.
            # method.name will always be a symbol, so we need to ensure that @merge_method comparion is in symbol format.
            merge_method = if @merge_method.is_a?(Symbol)
              @merge_method
            else
              @merge_method.parameterize(separator: "_").to_sym
            end

            method.name == merge_method
          end
        else
          methods.detect(&:is_default)
        end
      end
    end
  end

  def commit_message_headline
    async_default_merge_message_parts.then do |parts|
      parts[0]
    end.sync
  end

  def commit_message_body
    async_default_merge_message_parts.then do |parts|
      parts[1]
    end.sync
  end

  def async_default_merge_message_parts
    return @default_merge_message_parts if defined?(@default_merge_message_parts)

    @default_merge_message_parts = pull_request.async_head_user.then do
      merge_method.then do |method|
        @pull_request.determine_merging_message(method, nil, nil)
      end
    end
  end

  def bypass_requirements
    @bypass_requirements || false
  end
end
