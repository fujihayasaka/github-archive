# typed: true
# frozen_string_literal: true

module Repository::IssueDependency
  extend T::Helpers
  extend ActiveSupport::Concern
  include MemexProjectColumn::IDataSource

  requires_ancestor { Repository }

  ISSUES_QUERY_COUNT_LIMIT = 5000
  TYPEAHEAD_PAGE_SIZE = 30
  RECOMMENDED_LABELS_LIMIT = 500
  private_constant :ISSUES_QUERY_COUNT_LIMIT

  class_methods do
    def open_issue_and_pr_counts(repository_ids:, return_nil_on_failure: false)
      if return_nil_on_failure
        begin
          Issue.
            where(state: :open, repository_id: repository_ids, user_hidden: false).
            group(:repository_id, :has_pull_request).
            count
        rescue ActiveRecord::ActiveRecordError
          nil
        end
      else
        Issue.
          where(state: :open, repository_id: repository_ids, user_hidden: false).
          group(:repository_id, :has_pull_request).
          count
      end
    end
  end

  # Finds if the Repository can use the Copilot SWE Agent.
  #
  # Returns true or false
  def copilot_swe_agent_enabled?(viewer)
    repo = T.cast(self, Repository) # rubocop:todo GitHub/AvoidCast

    return false unless copilot_swe_agent_eligible?(viewer)

    copilot = Apps::Privileged.integration(:copilot_swe_agent)
    return false unless copilot

    if repo.owner
      # Check for the Copilot repo access policy
      repo.owner&.copilot_swe_agent_enabled_for?(repo)
    else
      # According to folks in #repos we should never hit this case in practice so lets raise an error
      # if we do.
      raise ArgumentError, "Repository owner not found for #{repo.name_with_display_owner}"
    end
  end

  # Checks if the viewer can use Copilot SWE Agent on this repository with write permissions.
  #
  # Returns true if both conditions are met, false otherwise
  def copilot_swe_agent_enabled_with_write_permissions?(viewer)
    repo = T.cast(self, Repository) # rubocop:todo GitHub/AvoidCast

    # Check if Copilot SWE Agent is enabled for this viewer and repository
    return false unless copilot_swe_agent_enabled?(viewer)

    # Check if the viewer has write permissions to this repository
    repo.writable_by?(viewer)
  end

  # Finds existing Labels for this Repository.
  #
  # label_names - Array of Integer label IDs.
  #
  # Returns an Array of Label objects.
  def find_labels(label_ids)
    labels.where(id: label_ids).to_a
  end

  # Public: Find Labels with the given names, case-insensitive, in this Repository.
  #
  # names - a single String or an Array of Strings
  #
  # Returns an ActiveRecord relation.
  def find_labels_by_name(names)
    labels.with_name(names)
  end

  # Finds existing Labels for this Repository.
  #
  # names - Array of Integer label IDs input by a user.
  #
  # Returns an Array of Label objects.
  def load_labels(ids)
    label_loader.fetch ids
  end

  # Helper method to find the 'help wanted' label
  #
  # returns Label or nil
  def help_wanted_label
    return @help_wanted_label if defined?(@help_wanted_label)
    @help_wanted_label = T.unsafe(labels).help_wanted || T.unsafe(labels).similar_to_help_wanted
  end

  # Helper method to find the 'good first issue' label
  #
  # returns Label or nil
  def good_first_issue_label
    return @good_first_issue_label if defined?(@good_first_issue_label)
    @good_first_issue_label = T.unsafe(labels).good_first_issue || T.unsafe(labels).similar_to_good_first_issue
  end

  def label_loader
    @label_loader ||= GitHub::LabelLoader.new(self)
  end

  # Returns a sorted collection of Labels for this Repository.
  #
  # issue_or_pr - Optional Issue or PullRequest. When provided, the labels that
  #   have already been applied to this object are sorted to the top of the
  #   returned list.
  #
  # Returns an Array of Label objects.
  def sorted_labels(issue_or_pr: nil, cache_label_html: false, limit: nil)
    labels_scope = labels.order("name")
    label_list = nil

    if limit
      if issue_or_pr
        labels_scope = labels_scope.limit(limit)

        # Make sure existing labels are returned (increasing the limit)
        existing_labels = (issue_or_pr.is_a?(PullRequest) ? issue_or_pr.issue : issue_or_pr).labels
        label_list = (labels_scope.to_a + existing_labels.to_a).uniq.sort_by(&:name)
      else
        labels_scope = labels_scope.limit(limit)
        label_list = labels_scope
      end
    else
      label_list = labels_scope
    end

    available_labels = Label.smart_sort(label_list, false)

    if issue_or_pr
      issue = issue_or_pr.is_a?(PullRequest) ? issue_or_pr.issue : issue_or_pr
      available_labels = available_labels
        .partition { |l| issue.unique_label_ids.include?(l.id) }
        .flatten
    end

    Promise.all(available_labels.map(&:async_name_html)).sync if cache_label_html

    available_labels
  end

  def sorted_labels_for_recommendations(limit: RECOMMENDED_LABELS_LIMIT)
    return [] if limit.nil? || limit <= 0

    labels_by_issues_count = Label.by_issues_count(repo: self, limit: limit)
    labels_count = labels_by_issues_count.length

    if labels_count == 0
      # If a repository has no open issues with labels assigned we will fall into this case
      label_list = labels.order(updated_at: :desc).limit(limit)
      Label.smart_sort(label_list, false)
    elsif labels_count < RECOMMENDED_LABELS_LIMIT && labels_count < labels.count
      labels_list = labels.where("id NOT IN (?)", labels_by_issues_count.pluck(:id)).order("updated_at desc").limit(RECOMMENDED_LABELS_LIMIT - labels_count)
      labels_by_issues_count.to_a + labels_list.to_a
    else
      labels_by_issues_count
    end
  end

  def sorted_labels_containing_keyword(issue_or_pr: nil, contains:)
    filtered_labels = contains != "" ? labels.where("lowercase_name LIKE ?", "%#{contains.downcase}%") : labels
    filtered_labels = filtered_labels.order("name")
    filtered_labels = filtered_labels.limit(TYPEAHEAD_PAGE_SIZE)

    available_labels = Label.smart_sort(filtered_labels, false)
    if issue_or_pr
      issue = issue_or_pr.is_a?(PullRequest) ? issue_or_pr.issue : issue_or_pr
      available_labels = available_labels # sort selected ones to the top
        .partition { |l| issue.unique_label_ids.include?(l.id) }
        .flatten
    end

    Promise.all(available_labels.map(&:async_name_html)).sync

    available_labels
  end

  included do
    T.bind(self, T.class_of(Repository))

    batch_method(:open_issues_count) do |repos|
      counts = Issue.open_issues.not_spammy.where(repository_id: repos.map(&:id)).group(:repository_id).except(:order).count
      repos.index_with do |repo|
        counts[repo.id].to_i
      end
    end
  end

  def help_wanted_issues_count
    @help_wanted_issues_count ||= begin
      return 0 unless community_profile = self.community_profile
      community_profile.help_wanted_issues_count
    end
  end

  def good_first_issue_issues_count
    @good_first_issue_issues_count ||= begin
      return 0 unless community_profile = self.community_profile
      community_profile.good_first_issue_issues_count
    end
  end

  ##
  # Pull Requests

  # A performance-aware method to count the number of open requests for a
  # repository.
  #
  # viewer - The User who is viewing the count (current_user)
  #
  # Returns the number of open requests as an Integer.
  def open_pull_request_count_for(viewer, limit: ISSUES_QUERY_COUNT_LIMIT)
    @open_pull_request_count_for ||= {}
    @open_pull_request_count_for[[viewer, limit]] ||= begin
      # Potentially hide spammy issues
      show_spam = viewer && (viewer_is_owner?(viewer) || (viewer.site_admin? && viewer.show_spammy_issues_to_staff_enabled?))
      if T.unsafe(self).spammy? && !show_spam
        0
      else
        scope = issues.filter_spam_for(viewer, show_spam_to_staff: show_spam, skip_user_filter_if_not_spammy: true)

        # Apply the specified limit.
        # We started adding 1 to the limit in
        # https://github.com/github/github/pull/44952 so that we would know if
        # the limit was crossed or not.
        scope = scope.limit(limit + 1)
        scope.where("state = 'open' and has_pull_request = 1").count
      end
    end
  end

  def open_issue_count_for(viewer, limit: ISSUES_QUERY_COUNT_LIMIT)
    @open_issue_count_for ||= {}
    @open_issue_count_for[[viewer, limit]] ||= begin
      # Potentially hide spammy issues
      show_spam = viewer && (viewer_is_owner?(viewer) || (viewer.site_admin? && viewer.show_spammy_issues_to_staff_enabled?))
      if T.unsafe(self).spammy? && !show_spam
        0
      else
        scope = issues.filter_spam_for(viewer, show_spam_to_staff: show_spam, skip_user_filter_if_not_spammy: true)

        # Apply the specified limit.
        # We started adding 1 to the limit in
        # https://github.com/github/github/pull/44952 so that we would know if
        # the limit was crossed or not.
        scope = scope.limit(limit + 1)
        scope.where("state = 'open' and has_pull_request = 0").count
      end
    end
  end

  # These limits are one higher, because the default limit gets incremented by one
  # within `open_pull_request_count_for` and `open_issue_count_for`
  def set_open_issue_count_for(viewer, count, limit: ISSUES_QUERY_COUNT_LIMIT)
    @open_issue_count_for ||= {}
    @open_issue_count_for[[viewer, limit]] = [count, limit + 1].min
  end

  def set_open_pull_request_count_for(viewer, count, limit: ISSUES_QUERY_COUNT_LIMIT)
    @open_pull_request_count_for ||= {}
    @open_pull_request_count_for[[viewer, limit]] = [count, limit + 1].min
  end

  def open_pull_requests_on_base_ref(branch_name)
    issues.open_issues
    .joins(:pull_request)
    .where(pull_requests: { base_ref: Git::Ref.safe_ref_name(ref_names: branch_name) })
  end

  def github_owned?
    owner_display_login == "github"
  end

  def issue_forms_type_field_enabled?(viewer)
    return false if viewer.nil?
    return @issue_forms_type_field_enabled if defined?(@issue_forms_type_field_enabled)

    @issue_forms_type_field_enabled = T.must(owner).issue_types_enabled?
  end

  def memex_suggestion_hash
    async_memex_suggestion_hash.sync
  end

  def async_memex_suggestion_hash
    async_memex_project_column_value.then do |column_value|
      hash = column_value.to_hash
      hash.merge(pushedAt: pushed_at&.utc&.iso8601)
    end
  end

  sig { override.returns(MemexProjectColumnValue::Repository) }
  def memex_project_column_value
    async_memex_project_column_value.sync
  end

  sig { returns(::Promise[MemexProjectColumnValue::Repository]) }
  def async_memex_project_column_value
    async_archived?.then do |archived|
      MemexProjectColumnValue::Repository.new(
        id: id,
        is_forked: fork?,
        is_public: public?,
        is_archived: archived,
        has_issues: has_issues?,
        name: name,
        owner: owner_display_login,
        name_with_display_owner: name_with_display_owner,
        url: permalink,
      )
    end
  end

  def viewer_can_see_commenter_full_name?(viewer)
    return @viewer_can_see_commenter_full_name if defined? @viewer_can_see_commenter_full_name
    async_viewer_can_see_commenter_full_name?(viewer).sync
  end

  # https://github.com/github/special-projects/issues/1112
  # Returns true to enable display_commenter_full_name feature for public/internal scoped repositories for GHES only.
  # display_commenter_full_name is enabled by default for private scope across.
  def async_viewer_can_see_commenter_full_name?(viewer)
    return Promise.resolve(false) if !viewer&.user?

    # TODO issue_timeline: can we bypass all the async_ calls if we know we preloaded the appropriate associations

    self.async_owner.then do |owner|
      if T.must(owner).organization?
        self.async_organization.then do |org|
          T.must(owner).async_business.then do |business|
            if viewer_can_see_commenter_full_name_for_the_setting_enabled?(business)
              if business.present?
                business.display_commenter_full_name_for_repo?(visibility: self.visibility.to_sym, viewer: viewer) ||
                T.must(org).display_commenter_full_name_for_repo?(visibility: self.visibility.to_sym, viewer: viewer)
              else
                T.must(org).display_commenter_full_name_for_repo?(visibility: self.visibility.to_sym, viewer: viewer)
              end
            else
              false
            end
          end
        end
      else
        false
      end
    end
  end

  def is_valid_enterprise_instance_to_show_commenter_full_name_setting?
    GitHub.single_business_environment?
  end

  def viewer_can_see_commenter_full_name_for_the_setting_enabled?(business)
    default_private_scope_enable_for_all = true

    if !is_valid_enterprise_instance_to_show_commenter_full_name_setting?
      if self.public? || self.internal?
        false
      else
        default_private_scope_enable_for_all
      end
    else
      if business.present? && (self.public? || self.internal?)
        setting_enabled = business.display_commenter_full_name_setting_enabled?
        setting_enforced = business.display_commenter_full_name_enforced?

        setting_enforced == true ? true : setting_enabled
      else
        default_private_scope_enable_for_all
      end
    end
  end

  # Public: The preferred ISSUE_TEMPLATE file from the Repository root.
  #
  # Returns a TreeEntry or nil.
  def preferred_issue_template
    preferred_file(:issue_template)
  end

  def async_preferred_issue_template
    async_preferred_file(:issue_template)
  end

  def viewer_is_owner?(viewer)
    return false unless viewer

    viewer.user? && viewer.id == owner_id
  end

  def copilot_swe_agent_eligible?(viewer)
    # Viewer is an optional parameter, as it is called from a few places without a viewer
    return false if self.public? && !self.owner&.feature_flag_enabled_or_raise?(:copilot_swe_agent_public_repos) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

    return false if self.feature_flag_enabled_or_raise?(:copilot_swe_agent_disallow) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

    # This FF is staff-shipped to enable staff and ensure backwards compatibility
    return true if self.feature_flag_enabled_or_raise?(:copilot_swe_agent) || self.owner&.feature_flag_enabled_or_raise?(:copilot_swe_agent) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

    # Check if the viewer is a bot and if it is the Copilot SWE Agent
    return true if viewer.is_a?(Bot) && viewer == Apps::Privileged.integration(:copilot_swe_agent)&.bot

    # Returns true if the viewer is nil - this should only happen when getting twirp secrets for sweagentd
    # See /twirp/actions/core/v1/get_integration_job_secrets.rb
    return true if viewer.nil?

    # Check copilot user policies
    viewer.is_a?(User) && Copilot::Public::User.new(viewer).swe_agent_enabled?
  end
end
