# typed: false
# frozen_string_literal: true

module Stafftools
  module RepositoryViews
    class AdminView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      include Stafftools::LargeFilesView::PreviewTogglerHelper
      include Stafftools::Sentry

      class UnknownConfigurationSettingSource < StandardError
      end

      attr_reader :repository, :porter_status

      # Listed in menu-display, value format
      DISABLE_REPO_REASONS = [
        ["private information", "private_information"],
        ["size", "size"],
        ["abuse at scale", "tos"],
        ["tos", "tos"],
        ["trademark", "trademark"]
      ].freeze

      def page_title
        "#{repository.name_with_owner} - Admin"
      end

      def importer_view
        if GitHub.porter_available?
          @importer_view ||= Stafftools::RepositoryViews::ImporterView.new(repository: repository, porter_status: porter_status)
        else
          nil
        end
      end

      def mirror
        repository.mirror
      end

      def mirror_sentry_link
        sentry_query_link(
          [Stafftools::Sentry::GITHUB_USER_PROJECT_ID],
          "repo_id:#{repository.id}"
        )
      end

      def mirror_timestamp
        # rubocop:todo GitHub/DoNotUseGlobalKv
        @mirror_timestamp ||= GitHub.kv.get("mirror-timestamp:#{repository.id}").value { "Unavailable" }
        # rubocop:enable GitHub/DoNotUseGlobalKv
      end

      def mirror_result
        # rubocop:todo GitHub/DoNotUseGlobalKv
        result = GitHub.kv.get("mirror-result:#{repository.id}").value { "failed" }
        # rubocop:enable GitHub/DoNotUseGlobalKv
        return "succeeded" if result == "success"
        result
      end

      def dmca?
        repository.access.dmca?
      end

      def archived?
        repository.archived?
      end

      def disabled?
        repository.access.disabled?
      end

      def disabled_at
        repository.access.disabled_at
      end

      def disabler_login
        return unless repository_access.disabler
        repository_access.disabler.login
      end

      def disabling_reason
        repository.access.disabling_reason
      end

      def invitation_rate_limit_overridden?
        RepositoryInvitationRateLimitOverride.overridden?(repository)
      end

      def invitation_rate_limit_override_expiration
        RepositoryInvitationRateLimitOverride.override_expiration_string
      end

      # force controls
      def setting_source_detail_text(target)
        if target == GitHub
          "the instance level"
        elsif target.kind_of?(::User)
          "the owner level"
        else
          if target.present?
            # We have no idea where it's coming from, this should only happen
            # when we change cascading and need to add another case here.
            # Note that if target is nil, we're just dealing with the default
            # hard-coded value and the setting is not set anywhere.
            boom = UnknownConfigurationSettingSource.new \
              "Unexpected source for setting. setting_source_detail_text \
              needs to be updated to support #{target.class}"
            boom.set_backtrace(caller)
            Failbot.report!(boom, "code.namespace": target.class)
          end
          "a higher level"
        end
      end

      def force_rejection_inherited_policy?
        repository.force_push_rejection_inherited? && repository.force_push_rejection_policy?
      end

      def force_detail_text
        case repository.force_push_rejection
        when false
          "Allowed"
        when "all"
          "Blocked"
        when "default"
          "Blocked on the default branch"
        end
      end

      def force_rejection_choices
        choices = [
          ["Allow", "false"],
          ["Block", "all"],
          ["Block to the default branch", "default"],
        ]

        if repository.force_push_rejection_original_value.nil?
          # There's no manual setting yet, so we're using git's default
          choices.unshift(["git's default (Allow)", nil])
        elsif repository.force_push_rejection_local? && repository.force_push_rejection_default_source
          choices << ["Use default from #{setting_source_detail_text(repository.force_push_rejection_default_source)}", "_clear"]
        elsif repository.force_push_rejection_local?
          # There's no setting that will cascade, so we'll use git's default
          choices << ["Clear and use git’s default (Allow)", "_clear"]
        end

        choices
      end

      def ssh_choices
        choices = [
          %w[Enabled true],
          %w[Disabled false],
        ]

        if repository.ssh_local? && repository.ssh_default_source
          choices << ["Use default from #{setting_source_detail_text(repository.ssh_default_source)}", "_clear"]
        elsif repository.ssh_local?
          # There's no setting that will cascade, so we'll use git's default
          choices << ["Clear and use default (Enabled)", "_clear"]
        end

        choices
      end

      # Maximum object size controls
      def max_object_size_detail_text
        if repository.max_object_size_inherited? ||
          (repository.max_object_size == Configurable::MaxObjectSize::DEFAULT_MAX_OBJECT_SIZE && !repository.max_object_size_local?)
          return "Inherited default (#{repository.max_object_size} MB)"
        end

        case repository.max_object_size
        when 0
          "Unlimited"
        when 1000
          "1 GB"
        else
          "#{repository.max_object_size} MB"
        end
      end

      def max_object_size_choices
        choices = [
          ["1MB", 1],
          ["2MB", 2],
          ["3MB", 3],
          ["4MB", 4],
          ["5MB", 5],
          ["10MB", 10],
          ["15MB", 15],
          ["25MB", 25],
          ["50MB", 50],
          ["75MB", 75],
          ["100MB", 100],
          ["150MB", 150],
          ["200MB", 200],
          ["250MB", 250],
          ["300MB", 300],
          ["350MB", 350],
          ["500MB", 500],
          ["750MB", 750],
          ["1GB", 1000],
        ]

        if repository.max_object_size_local?
          default_source = setting_source_detail_text(repository.max_object_size_default_source)
          default_value = repository.max_object_size_default_value
          choices.unshift(["Inherited default from #{default_source} (#{default_value} MB)", "_clear"])
        end

        if GitHub.unlimited_max_object_size_enabled?
          choices << ["Unlimited", 0]
        end

        choices
      end

      def disable_repo_reason_choices
        DISABLE_REPO_REASONS
      end

      # Repository disk quota controls

      def disk_quota_detail_text(kind)
        quota = repository.disk_quota(kind: kind)
        case quota
        when 0
          "Unlimited"
        when repository.default_disk_quota(kind: kind)
          "Default (#{quota} GB)"
        else
          "#{quota} GB"
        end
      end

      def disk_quota_choices
        [
          ["10 GB", 10],
          ["20 GB", 20],
          ["50 GB", 50],
          ["75 GB", 75],
          ["100 GB", 100],
          ["200 GB", 200],
          ["Unlimited", 0],
        ]
      end

      def disk_quota_octicon(kind)
        case kind
        when :warn
          "bell"
        when :lock
          "shield-lock"
        end
      end

      # graph controls

      def graph_allowed?
        repository.graph_cache_enabled?
      end

      def graph_button_disabled
        return if graph_allowed?
        "disabled"
      end

      def graph_button_text
        graph_allowed? ? "Disable" : "Enable"
      end

      def graph_detail_text
        graph_allowed? ? "enabled" : "disabled"
      end

      # public_push controls
      def public_push_button_text
        repository.public_push? ? "Block" : "Allow"
      end

      # public_push controls
      def public_push_detail_text
        repository.public_push? ? "allowed" : "blocked"
      end

      # Allow changing visibility of public unforked repos, and
      # forks where visibility differs from the root repository.
      def show_permission_toggle?
        return true if repository.public? && !repository.fork? && repository.all_forks_count == 0

        return false unless repository.fork?
        return false if repository.root.nil?

        repository.public? != repository.root.public?
      end

      def permission_toggle_type
        repository.public? ? "private" : "public"
      end

      # Does owner's billing plan prevent toggling this repo to private?
      def make_private_blocked_on_plan?
        GitHub.billing_enabled? && repository.public? && !repository.fork? && repository.owner.at_private_repo_limit?
      end

      def transferring?
        repository.pending_transfer?
      end

      def transfer_created_at
        repository.pending_transfer.created_at
      end

      def transfer_requester
        repository.pending_transfer.requester
      end

      def transfer_target
        repository.pending_transfer.target
      end

      def anonymous_access_state
        repository.anonymous_git_access_enabled? ? "enabled" : "disabled"
      end

      def toggled_anonymous_access
        !repository.anonymous_git_access_enabled?
      end

      def toggled_anonymous_access_action
        toggled_anonymous_access ? "Enable" : "Disable"
      end

      def toggled_anonymous_access_action_gerund
        toggled_anonymous_access ? "enabling" : "disabling"
      end

      def anonymous_access_locked?
        repository.anonymous_git_access_locked?
      end

      def anonymous_access_locked_policy?
        repository.anonymous_git_access_locked_policy?
      end

      def anonymous_access_locked_disabled
        anonymous_access_locked_policy? ? "disabled" : ""
      end

      def org_interaction_limits_enabled?
        GitHub.interaction_limits_enabled? &&
        repository.owner.organization? &&
        RepositoryInteractionAbility.has_active_limits?(repository.owner)
      end

      def pending_apply_content_warning_job?
        ApplyContentWarningJob.status(repository)&.state.in? %w[started pending]
      end

      def error_apply_content_warning_job?
        ApplyContentWarningJob.status(repository)&.state.in? %w[error]
      end

      def pending_remove_content_warning_job?
        RemoveContentWarningJob.status(repository)&.state.in? %w[started pending]
      end

      def error_remove_content_warning_job?
        RemoveContentWarningJob.status(repository)&.state.in? %w[error]
      end

      def pending_access_disable_job?
        repository.disable_access_job_status.in? %w[started pending]
      end

      def error_access_disable_job?
        repository.disable_access_job_status.in? %w[error]
      end

      def pending_access_enable_job?
        repository.enable_access_job_status.in? %w[started pending]
      end

      def token_scanning_features
        @token_scanning_features ||= SecretScanning::Features::Repo::TokenScanning.new(repository)
      end

      def public_scanning_features
        @public_scanning_features ||= SecretScanning::Features::Repo::PublicScanning.new(repository)
      end

      def show_token_scanning?
        token_scanning_features.stafftools_available? || public_scanning_features.stafftools_available?
      end

      private

      def repository_access
        @repository_access ||= repository.access
      end

      def git_lfs_configurable
        repository
      end

      def community_profile
        @community_profile ||= repository.community_profile || CommunityProfile.new(repository: repository)
      end
    end
  end
end
