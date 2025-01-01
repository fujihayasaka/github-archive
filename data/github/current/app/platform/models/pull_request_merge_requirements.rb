# typed: true
# frozen_string_literal: true

class Platform::Models::PullRequestMergeRequirements
  include GitHub::Memoizer

  attr_reader :pull_request, :viewer

  def initialize(pull_request, merge_action, merge_method, bypass_requirements, viewer)
    @pull_request = pull_request
    @merge_action = merge_action
    @merge_method = merge_method
    @bypass_requirements = bypass_requirements
    @viewer = viewer
  end

  def commit_author
    Platform::Loaders::ActiveRecord.load(::User, @pull_request.user_id, column: :id, case_sensitive: false).then do |user|
      user = T.must(user)
      promises = [
        Platform::Loaders::ActiveRecord.load(::Repository, @pull_request.repository_id, column: :id, case_sensitive: false),
        user.async_primary_user_email,
        user.async_primary_private_user_email,
        user.async_stealth_user_email,
        user.async_profile,
      ]
      Promise.all(promises).then do |repository, _|
        user.default_author_email(repository) || user.git_author_email
      end
    end
  end

  def state
    Promise.all([
      @pull_request.async_repository,
      @pull_request.async_base_repository,
      @pull_request.async_head_repository,
      @pull_request.async_merge_queue
    ]).then do |result|
      merge_queue = result.pop
      repositories = result

      if merge_queue
        GitHub::PrefillAssociations.prefill_associations(merge_queue, :repository, available_records: repositories)
      end

      networks = repositories.compact.map(&:async_network)
      users = [@pull_request.async_base_user, @pull_request.async_head_user, @pull_request.async_user]

      Promise.all(networks + users).then do
        @pull_request.enqueue_mergeable_update

        next :unknown if @pull_request.currently_mergeable?.nil?

        async_conditions.then do |conditions|
          has_failing_conditions = conditions.any? { |c| c.result == :failed }
          has_failing_conditions ? :unmergeable : :mergeable
        end
      end
    end
  end

  memoize def async_conditions
    merge_method.then do |selected_merge_method|
      ::MergeConditions::Evaluator.async_evaluate(pull_request, viewer, selected_merge_method, skip_checks: false)
    end
  end

  # The merge action being used to evaluate mergeability. See async_evaluated_merge_action
  def merge_action
    async_evaluated_merge_action.then do |action|
      action.name
    end
  end

  # The AllowableMergeAction being used to evaluate mergeability. It was either determined by an argument or the first allowable action for the user.
  def async_evaluated_merge_action
    return @evaluated_merge_action if defined?(@evaluated_merge_action)

    @evaluated_merge_action = ::PullRequest::AllowableMergeAction.for(pull_request: pull_request, viewer: viewer).then do |actions|
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

      # If we reached this point, fallack to the first (which may or may not be allowed)
      action || actions.first
    end
  end

  # The merge method being used to evaluate mergeability. See async_evaluated_merge_method
  def merge_method
    async_evaluated_merge_method.then do |method|
      method.name
    end
  end

  def async_evaluated_merge_method
    return @evaluated_merge_method if defined?(@evaluated_merge_method)

    async_evaluated_merge_action.then do |action|
      action.merge_methods.then do |methods|
        if @merge_method && action.name != :merge_queue
          methods.detect { |m| m.name == @merge_method }
        else
          methods.detect(&:is_default)
        end
      end
    end
  end

  def commit_message_headline
    async_default_merge_message_parts.then do |parts|
      parts[0]
    end
  end

  def commit_message_body
    async_default_merge_message_parts.then do |parts|
      parts[1]
    end
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
