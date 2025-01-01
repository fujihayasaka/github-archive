# typed: true
# frozen_string_literal: true

module Repository::PullRequestDependency
  extend ActiveSupport::Concern
  include Configurable::SquashMergeCommitTitle
  include Configurable::SquashMergeCommitMessage
  include Configurable::MergeCommitTitle
  include Configurable::MergeCommitMessage
  include Configurable::RestrictNonCommentPullRequestReviews

  extend T::Helpers

  requires_ancestor { Repository }

  # MergeMethodError is raised either
  # 1. when attempting to disable all merge methods, or
  # 2. when there is a protected branch rule with linear history requirement,
  #    attempting to disable both squash and merge.
  class MergeMethodError < ArgumentError
    attr_reader :reason
    def initialize(reason, msg = nil)
      case reason
      when :protected_branch_policy
        @reason = :protected_branch_policy
        msg = "Sorry, you need to allow either squash or rebase merge strategies, or both."
      when :no_merge_method
        @reason = :no_merge_method
        msg = "Sorry, you need to allow at least one merge strategy."
      when :no_squash_merge_strategy
        @reason = :no_squash_merge_strategy
        msg = "Sorry, you need to allow the squash merge strategy in order to set the default squash commit message title or message."
      when :invalid_squash_commit_setting_combo
        @reason = :invalid_squash_commit_setting_combo
        msg = "Sorry, invalid setting combination. The following are valid combinations for the squash commit title and message: PR_TITLE and PR_BODY, PR_TITLE and BLANK, PR_TITLE and COMMIT_MESSAGES, COMMIT_OR_PR_TITLE and COMMIT_MESSAGES."
      when :invalid_merge_commit_setting_combo
        @reason = :invalid_merge_commit_setting_combo
        msg = "Sorry, invalid setting combination. The following are valid combinations for the merge commit title and message: PR_TITLE and PR_BODY, PR_TITLE and BLANK, MERGE_MESAGE and PR_TITLE."
      when :no_merge_strategy
        @reason = :no_merge_strategy
        msg = "Sorry, you need to allow the merge commit strategy in order to set the default merge commit message title and message."
      when /conflicting.*configuration/
        @reason = reason.to_sym
        msg = "Sorry, #{msg}, please check the current settings and try again if it is incorrect."
      else
        @reason = :protected_branch_policy
        msg = "Sorry, you need to allow either squash or rebase merge strategies, or both."
      end
      super(msg)
    end
  end

  # Public: Return the default merge method for the given viewer.
  #
  # viewer - The User viewing a pull request in the repository.
  #
  # This is based on the last used merge method by the viewer and
  # the allowed/disallowed merge methods set on the repository.
  sig { params(viewer: T.nilable(User)).returns(Symbol) }
  def default_merge_method_for(viewer)
    if sticky_merge_method(viewer) == "squash" && squash_merge_allowed?
      :squash
    elsif sticky_merge_method(viewer) == "rebase" && rebase_merge_allowed?
      :rebase
    elsif merge_commit_allowed?
      :merge
    elsif squash_merge_allowed?
      :squash
    elsif rebase_merge_allowed?
      :rebase
    else
      :merge
    end
  end

  sig { params(user: T.nilable(User)).returns(String) }
  def sticky_merge_method(user)
    return "merge_commit" if id.nil? || user.nil?
    result = GitHub.kv.get("repo.merge_method.#{id}.user.#{user.id}") # rubocop:todo GitHub/DoNotUseGlobalKv
    result.value { nil } || "merge_commit"
  end

  sig { params(user: User, val: String).void }
  def set_sticky_merge_method(user, val)
    GitHub.kv.set("repo.merge_method.#{id}.user.#{user.id}", val) # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  ASYNC_FALSE = T.let(Promise.resolve(T.let(false, T::Boolean)), Promise[T::Boolean])
  IS_NOT_TRUE_STRING = T.let(
    -> (value) { value != "true" },
    T.proc.params(value: T.untyped).returns(T::Boolean)
  )

  sig { returns(Promise[PullRequest::MergeMethodSettings]) }
  def async_allowable_merge_methods
    promises = [
      async_merge_commit_allowed?,
      async_squash_merge_allowed?,
      async_rebase_merge_allowed?,
    ].map do |promise|
      with_async_database_error_fallback(
        promise.then { PullRequest::MergeMethodSettings::Value.from_bool(_1) },
        fallback: PullRequest::MergeMethodSettings::Value::LoadError
      )
    end

    Promise.all(promises).then do |merge_commit, squash_merge, rebase_merge|
      PullRequest::MergeMethodSettings.new(
        merge_commit: T.must(merge_commit),
        squash_merge: T.must(squash_merge),
        rebase_merge: T.must(rebase_merge),
      )
    end
  end

  sig { returns(Promise[T::Boolean]) }
  def async_merge_commit_allowed?
    return ASYNC_FALSE if id.nil?
    async_merge_commits_allowed?
  end

  sig { returns(T::Boolean) }
  def merge_commit_allowed?
    async_merge_commit_allowed?.sync
  end

  sig { returns(Promise[T::Boolean]) }
  def async_squash_merge_allowed?
    return ASYNC_FALSE if id.nil?
    async_squash_commits_allowed?
  end

  sig { returns(T::Boolean) }
  def squash_merge_allowed?
    async_squash_merge_allowed?.sync
  end

  sig { returns(Promise[T::Boolean]) }
  def async_rebase_merge_allowed?
    return ASYNC_FALSE if id.nil?
    async_rebase_commits_allowed?
  end

  sig { returns(T::Boolean) }
  def rebase_merge_allowed?
    async_rebase_merge_allowed?.sync
  end

  # Use PR Title and Description as default
  # merge commit & title message
  sig { returns(T::Boolean) }
  def use_merge_pr_body_as_default?
    merge_commit_title_pr_title_enabled? && merge_commit_message_pr_body_enabled?
  end

  # Use PR Title as default merge commit title
  sig { returns(T::Boolean) }
  def use_merge_pr_title_as_default?
    merge_commit_title_pr_title_enabled?
  end

  # Use PR Title and Description as default
  # squash merge commit title & message
  sig { returns(T::Boolean) }
  def use_squash_pr_body_as_default?
    (squash_pr_title_enabled? || squash_merge_commit_title_pr_title_enabled?) && squash_commit_message_pr_body_enabled?
  end

  # Use PR Title as default squash merge commit title
  # and leave the commit message blank
  sig { returns(T::Boolean) }
  def use_squash_pr_title_as_default?
    (squash_pr_title_enabled? || squash_merge_commit_title_pr_title_enabled?) &&
    squash_commit_message_blank_enabled?
  end

  # Use the PR Title as the default squash merge commit title
  # and the commit details as the commit message
  sig { returns(T::Boolean) }
  def use_squash_pr_commits_as_default?
    (squash_pr_title_enabled? || squash_merge_commit_title_pr_title_enabled?) &&
    (squash_commit_message_commit_messages_enabled? || squash_merge_commit_message_setting.nil?)
  end

  def validate_merge_settings_update!(merge_allowed: nil, squash_allowed: nil, rebase_allowed: nil, squash_merge_commit_title_setting: nil, squash_merge_commit_message_setting: nil, merge_commit_title_setting: nil, merge_commit_message_setting: nil)
    any_linear_history = protected_branches.where.not(linear_history_requirement_enforcement_level: :off).any?

    if merge_allowed && !squash_allowed && !rebase_allowed && any_linear_history
      raise MergeMethodError.new(:protected_branch_policy)
    end

    if !merge_allowed && !squash_allowed && !rebase_allowed
      raise MergeMethodError.new(:no_merge_method)
    end

    if squash_merge_commit_title_setting || squash_merge_commit_message_setting
      # Cannot update the settings for squash merging if the strategy is disabled.
      if !squash_allowed && (
        squash_merge_commit_title_setting_updated?(squash_merge_commit_title_setting) ||
        squash_merge_commit_message_setting_updated?(squash_merge_commit_message_setting)
      )
        raise MergeMethodError.new(:no_squash_merge_strategy)
      end

      # check for invalid title setting options
      if !squash_merge_commit_title_setting.nil? && !Configurable::SquashMergeCommitTitle::VALUES.include?(squash_merge_commit_title_setting)
        raise MergeMethodError.new(:invalid_squash_commit_setting_combo)
      end

      # check for invalid message setting options
      if !squash_merge_commit_message_setting.nil? && !Configurable::SquashMergeCommitMessage::VALUES.include?(squash_merge_commit_message_setting)
        raise MergeMethodError.new(:invalid_squash_commit_setting_combo)
      end

      # Check for valid setting options
      if %w[PR_BODY BLANK].include?(squash_merge_commit_message_setting) && squash_merge_commit_title_setting != "PR_TITLE"
        raise MergeMethodError.new(:invalid_squash_commit_setting_combo)
      end

      if squash_merge_commit_title_setting == "COMMIT_OR_PR_TITLE" && squash_merge_commit_message_setting != "COMMIT_MESSAGES"
        raise MergeMethodError.new(:invalid_squash_commit_setting_combo)
      end
    end

    if merge_commit_title_setting || merge_commit_message_setting
      # Cannot update the settings for merging if the strategy is disabled.
      if !merge_allowed && (
        merge_commit_title_setting_updated?(merge_commit_title_setting) ||
        merge_commit_message_setting_updated?(merge_commit_message_setting)
      )
        raise MergeMethodError.new(:no_merge_strategy)
      end
      # check for valid setting options
      unless Configurable::MergeCommitTitle::VALUES.include?(merge_commit_title_setting)
        raise MergeMethodError.new(:invalid_merge_commit_setting_combo)
      end

      unless Configurable::MergeCommitMessage::VALUES.include?(merge_commit_message_setting)
        raise MergeMethodError.new(:invalid_merge_commit_setting_combo)
      end

      if %w[PR_BODY BLANK].include?(merge_commit_message_setting) && merge_commit_title_setting != PR_TITLE
        raise MergeMethodError.new(:invalid_merge_commit_setting_combo)
      end

      if merge_commit_title_setting == "MERGE_MESSAGE" && merge_commit_message_setting != "PR_TITLE"
        raise MergeMethodError.new(:invalid_merge_commit_setting_combo)
      end

      if merge_commit_title_setting == "PR_TITLE" && (!merge_commit_message_setting || merge_commit_message_setting == "PR_TITLE")
        raise MergeMethodError.new(:invalid_merge_commit_setting_combo)
      end
    end
  end

  # Public: Updates the merge settings for a pull request:
  # - Type of merges:
  #   - For each merge method, a param of `true` indicates that
  #     the method should be allowed, `false` that it should be blocked, and `nil`,
  #     that it should keep its current value.
  # - delete head branch after merging a pull request
  # - Always show the update branch button (for updating head branch) at the pull request page.
  # - Set the default commit title and message for squash merge commits and merge commits
  def update_merge_settings(user, merge_allowed: nil, squash_allowed: nil, rebase_allowed: nil, auto_merge_allowed: nil, delete_branch_allowed: nil, update_branch_allowed: nil, squash_pr_title_used_as_default: nil, squash_merge_commit_title_setting: nil, squash_merge_commit_message_setting: nil, merge_commit_title_setting: nil, merge_commit_message_setting: nil, validate_settings: true)
    ApplicationRecord::Domain::ConfigurationEntries.transaction do
      # Work around a Sorbet bug: explicitly assign the variables outside of
      # the transaction block so that reassigning them inside the block isn't
      # seen as a type change.
      merge_allowed = T.let(merge_allowed, T.nilable(T::Boolean))
      squash_allowed = T.let(squash_allowed, T.nilable(T::Boolean))
      rebase_allowed = T.let(rebase_allowed, T.nilable(T::Boolean))
      auto_merge_allowed = T.let(auto_merge_allowed, T.nilable(T::Boolean))

      transaction do
        merge_commit_currently_allowed = merge_commit_allowed?
        merge_allowed = merge_commit_currently_allowed if merge_allowed.nil?

        squash_commit_currently_allowed = squash_merge_allowed?
        squash_allowed = squash_commit_currently_allowed if squash_allowed.nil?

        rebase_commit_currently_allowed = rebase_merge_allowed?
        rebase_allowed = rebase_commit_currently_allowed if rebase_allowed.nil?

        auto_merge_currently_allowed = auto_merge_allowed?
        auto_merge_allowed = auto_merge_currently_allowed if auto_merge_allowed.nil?

        validate_merge_settings_update!(
          merge_allowed: merge_allowed,
          squash_allowed: squash_allowed,
          rebase_allowed: rebase_allowed,
          squash_merge_commit_title_setting: squash_merge_commit_title_setting,
          squash_merge_commit_message_setting: squash_merge_commit_message_setting,
          merge_commit_title_setting: merge_commit_title_setting,
          merge_commit_message_setting: merge_commit_message_setting
        ) if validate_settings

        begin
          if merge_allowed != merge_commit_currently_allowed
            if merge_allowed
              allow_merge_commits(actor: user)
            else
              disallow_merge_commits(actor: user)
            end

            instrument :change_merge_setting, {
              actor: user,
              merge_type: "merge_commit",
              enabled: !!merge_allowed,
            }
          end

          if squash_allowed != squash_commit_currently_allowed
            if squash_allowed
              allow_squash_commits(actor: user)
            else
              disallow_squash_commits(actor: user)
            end

            instrument :change_merge_setting, {
              actor: user,
              merge_type: "squash",
              enabled: !!squash_allowed,
            }
          end

          if rebase_allowed != rebase_commit_currently_allowed
            if rebase_allowed
              allow_rebase_commits(actor: user)
            else
              disallow_rebase_commits(actor: user)
            end

            instrument :change_merge_setting, {
              actor: user,
              merge_type: "rebase",
              enabled: !!rebase_allowed,
            }
          end

          if can_auto_merge_be_allowed? && auto_merge_allowed != auto_merge_currently_allowed
            if auto_merge_allowed
              allow_auto_merge(actor: user)
            else
              disallow_auto_merge(actor: user)
            end
          end

          # don't alter the state if the actor can't perform the action
          if can_modify_delete_branch_setting?(user)
            if delete_branch_allowed == false
              disallow_auto_deleting_branches(actor: user)
            elsif delete_branch_allowed == true
              allow_auto_deleting_branches(actor: user)
            end
          end

          # adjust setting of `always allowing to update branch`
          if update_branch_allowed == true
            allow_updating_branches(actor: user)
          elsif update_branch_allowed == false
            disallow_updating_branches(actor: user)
          end

          # adjust setting of `squash pr title`
          if squash_merge_commit_title_setting
            set_squash_merge_commit_title_setting(
              setting: squash_merge_commit_title_setting,
              actor: user
            )
          end

          if squash_merge_commit_message_setting
            set_squash_merge_commit_message_setting(
              setting: squash_merge_commit_message_setting,
              actor: user
            )
          end

          if merge_commit_title_setting
            set_merge_commit_title_setting(
              setting: merge_commit_title_setting,
              actor: user
            )
          end

          if merge_commit_message_setting
            set_merge_commit_message_setting(
              setting: merge_commit_message_setting,
              actor: user
            )
          end
        rescue Configuration::ConflictingRecordError => error
          raise MergeMethodError.new(
            "conflicting_#{error.setting_name}_configuration",
            "there was a conflict in updating the #{error.setting_name.gsub("_", " ")} setting"
          )
        end
      end
    end
  end

  # Public: The preferred PULL_REQUEST_TEMPLATE file from the Repository root.
  #
  # "Preferred" means the first template found in the repo that's for the
  # PULL_REQUEST_TEMPLATE type. This does not account for anything found in
  # global health files.
  #
  # Returns a TreeEntry or nil.
  def preferred_pull_request_template
    preferred_file(:pull_request_template)
  end

  def async_preferred_pull_request_template
    async_preferred_file(:pull_request_template)
  end

  # Public: Pull request templates for this repository, either from the local
  # repository or a global health files repository for an organization.
  #
  # Returns `PullRequestTemplate`s or nil.
  def pull_request_templates
    @_pull_request_templates ||= async_pull_request_templates.sync
  end

  # Public: Pull request templates for this repository, either from the local
  # repository or a global health files repository from a parent organization.
  #
  # Returns Promise<Array<PullRequestTemplate>>.
  def async_pull_request_templates
    Promise.all([async_default_branch_ref, async_root]).then do
      if local_pull_request_templates.any? || global_health_files_repository?
        Promise.resolve(local_pull_request_templates)
      else
        async_owner.then do |_owner|
          async_global_health_files_repo.then do |global_repository|
            next local_pull_request_templates unless global_repository.present?

            global_templates = global_repository.local_pull_request_templates
            global_templates.presence || local_pull_request_templates
          end
        end
      end
    end
  end

  # Returns a list of pull requst templates that exist in the repo
  def local_pull_request_templates
    @_pull_request_templates ||= PullRequestTemplate.wrap(
      PreferredFile.find_all(directory: directory(default_branch), type: :pull_request_template)
    )
  end

  # Public: Does this repo have a codeowners file at the default branch?
  #
  # Returns a Boolean.
  def codeowners?
    return @codeowners if defined? @codeowners
    @codeowners = preferred_files.exists?(:codeowners)
  end

  def merge_commit_title_setting_updated?(merge_commit_title_setting)
    merge_commit_title_setting != (self.new_record? ? MERGE_MESSAGE : self.merge_commit_title_setting)
  end

  def merge_commit_message_setting_updated?(merge_commit_message_setting)
    merge_commit_message_setting != (self.new_record? ? PR_TITLE : self.merge_commit_message_setting)
  end

  def squash_merge_commit_title_setting_updated?(squash_merge_commit_title_setting)
    squash_merge_commit_title_setting != (self.new_record? ? COMMIT_OR_PR_TITLE : self.squash_merge_commit_title_setting)
  end

  def squash_merge_commit_message_setting_updated?(squash_merge_commit_message_setting)
    squash_merge_commit_message_setting != (self.new_record? ? COMMIT_MESSAGES : self.squash_merge_commit_message_setting)
  end
end
