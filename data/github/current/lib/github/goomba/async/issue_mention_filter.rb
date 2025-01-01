# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Async
  # This filter serves a base class to a few other GitHub::Goomba::Async filters, and
  # provides common logic to find issue and discussion references in #async_scan.
  # This class is not intended to be used directly.  Please create a subclass that implements
  # #call_a and #call_gh to transform content.  See GitHub::Goomba::Async::RichIssueMentionFilter
  # for an example.
  class IssueMentionFilter < NodeFilter
    include GitHub::Goomba::Reference::Helpers

    SELECTOR = Goomba::Selector.new(match: "gh|issue-mention, a[gh|issue-mention], gh|discussion-mention, a[gh|discussion-mention]")
    ISSUE_ELEM_SELECTOR = Goomba::Selector.new(match: "gh|issue-mention")
    ISSUE_ATTR_SELECTOR = Goomba::Selector.new(match: "a[gh|issue-mention]")
    DISCUSSION_ATTR_SELECTOR = Goomba::Selector.new(match: "a[gh|discussion-mention]")

    def self.cache_key(context)
      return unless context[:cap_filter].present?
      "calculate_readable_references"
    end

    def initialize(*args)
      super
      # Issue references can be populated if any subclasses lookup issue mentions before
      # GitHub::Goomba::Async::IssueMentionFilter runs within GitHub::Goomba::GithubReferenceFilter.
      #
      # See GitHub::Goomba::Async::TrackingBlockFilter for an example of a subclass that can populate issue references.
      scratch[:issue_references] ||= {}
      scratch[:discussion_references] = {}
    end

    def selector
      SELECTOR
    end

    # Collect and authorize all issues mentioned for viewer against an optional Conditional Access Policy (CAP) Filter
    def async_scan_nodes
      @nodes.map do |node|
        if node =~ ISSUE_ATTR_SELECTOR
          data = JSON.parse(node["gh:issue-mention"])
          nwo, number = data["nwo"], data["number"]
        elsif node =~ DISCUSSION_ATTR_SELECTOR
          data = JSON.parse(node["gh:discussion-mention"])
          nwo, number = data["nwo"], data["number"]
        else
          nwo, number = node["nwo"], node["number"]
        end

        async_issue_or_discussion_reference(number.to_i, nwo).then do |reference|
          next unless reference

          promises = [reference.async_repo_and_owner]

          if reference.respond_to?(:async_pull_request)
            promises << reference.async_pull_request
          end

          Promise.all(promises)
        end
      end
    end

    def async_scan
      timer = Timer.start

      Promise.all(async_scan_nodes).then do
        GitHub.dogstats.distribution("reference_mentions.load_references.dist", timer.elapsed_ms)

        next unless calculate_readable_references?

        async_load_installation_for_source_repo(repository).then do
          async_calculate_references_readable_by(context[:viewer], context[:cap_filter])
        end
      end
    end

    def calculate_readable_references?
      context[:cap_filter].present?
    end

    # Matches a node to either <gh:(issue|discussion)-mention> or <a gh:(issue|discussion)-mention>
    # and calls the appropriate handler method.  This class does not handle any transformations itself
    # and instead relies on subclasses to provide transformation.
    def call(node)
      if (node =~ ISSUE_ATTR_SELECTOR) || (node =~ DISCUSSION_ATTR_SELECTOR)
        call_a(node)
      else
        call_gh(node)
      end
    end

    def call_a(node)
      raise NotImplementedError
    end

    def call_gh(node)
      raise NotImplementedError
    end

    def issue_mentions
      result[:issues] ||= []
    end

    def discussion_mentions
      result[:discussions] ||= []
    end

    def async_bot_can_access_issue_or_discussion?(repo, issue_or_discussion)
      return Promise.resolve(false) if repo.nil? || issue_or_discussion.nil?
      return Promise.resolve(false) unless current_user&.can_have_granular_permissions?

      if issue_or_discussion.is_a?(Issue)
        issue_or_discussion.async_pull_request.then do |pull_request|
          if pull_request.present?
            repo.resources.pull_requests.async_readable_by?(current_user)
          else
            repo.resources.issues.async_readable_by?(current_user)
          end
        end
      else
        # TODO: Discussions will end up here but we're not sure exactly what to
        # do about that yet.
        # https://github.com/github/github/pull/140918#issuecomment-621492555
        Promise.resolve(false)
      end
    end

    def async_calculate_references_readable_by(viewer, cap_filter)
      raise ArgumentError, "`cap_filter` must be present" if cap_filter.nil?
      timer = Timer.start

      references_by_issue = issue_references.group_by(&:issue)
      references_by_discussion = discussion_references.group_by(&:discussion)
      references_by_record = references_by_issue.merge references_by_discussion
      if cap_filter.is_a?(Hash) && cap_filter.has_key?(:cap_filter)
        cap_filter = cap_filter[:cap_filter]
      end
      accessible_records = cap_filter.authorized_resources(references_by_record.keys)

      promises = accessible_records.map do |accessible_record|
        accessible_record.async_repository.then do |record_repository|
          is_same_repo = record_repository.id == repository&.id
          if is_same_repo
            references_by_record[accessible_record].each { |r| r.readable = is_same_repo }
            next
          end

          accessible_record.async_readable_by?(viewer).then do |readable|
            references_by_record[accessible_record].each { |r| r.readable = readable }
          end
        end
      end
      Promise.all(promises).then do |result|
        GitHub.dogstats.distribution("reference_mentions.check_permissions.dist", timer.elapsed_ms,
          tags: ["number:#{references_by_record.size}"]
        )
        result
      end
    end

    def async_issue_or_discussion(number, owner_or_nwo)
      async_find_repository(owner_or_nwo).then do |repository|
        next Promise.resolve(nil) unless repository

        if deferred_authorization_checks_enabled?
          next async_find_issue_or_discussion(repository, number, search_parents: owner_or_nwo.blank?)
        end

        async_load_installation_for_target_repo(repository).then do
          if current_user&.can_have_granular_permissions?
            async_find_issue_or_discussion(repository, number, search_parents: owner_or_nwo.blank?).then do |issue_or_discussion|
              async_bot_can_access_issue_or_discussion?(repository, issue_or_discussion).then do |bot_can_access|
                next unless bot_can_access
                issue_or_discussion
              end
            end
          else
            async_can_access_repo?(repository).then do |user_can_access|
              next unless user_can_access
              async_find_issue_or_discussion(repository, number, search_parents: owner_or_nwo.blank?)
            end
          end
        end
      end
    end

    def async_issue_or_discussion_reference(number, owner_or_nwo)
      reference = issue_reference(owner_or_nwo, number)
      return Promise.resolve(reference) if reference

      async_issue_or_discussion(number, owner_or_nwo).then do |issue_or_discussion|
        next unless issue_or_discussion

        issue_or_discussion.async_repository.then do
          if issue_or_discussion.is_a?(Discussion)
            add_discussion_reference(owner_or_nwo, number, issue_or_discussion)
          else
            add_issue_reference(owner_or_nwo, number, issue_or_discussion)
          end
        end
      end
    end

    def async_find_issue_or_discussion(repository, number, search_parents: false)
      async_load_issue_or_discussion(repository, number).then do |issue_or_discussion|
        next issue_or_discussion if issue_or_discussion
        next unless search_parents

        # if the issue wasn't found, try searching up the parent chain but only when
        # no explicit repository reference was given (i.e., "foo/bar#33" won't
        # search in other repositories).
        repository.async_parent.then do |parent_repo|
          next unless parent_repo
          async_find_issue_or_discussion(parent_repo, number, search_parents: search_parents)
        end
      end
    end

    def async_load_issue_or_discussion(repository, number)
      Platform::Loaders::IssueOrDiscussionByNumber.load(repository.id, number.to_i).then do |issue_or_discussion|
        next unless issue_or_discussion
        # when authorization checks are deferred, the following
        # checks on whether the repo supports the issue or discussion type
        # is handled post-cache
        next issue_or_discussion if deferred_authorization_checks_enabled?

        if issue_or_discussion.is_a?(Issue)
          # PRs can't be disabled, so return the Issue
          # for a PR even if Issues are disabled
          next issue_or_discussion if repository.has_issues || issue_or_discussion.pull_request?
        elsif issue_or_discussion.is_a?(Discussion)
          if repository.discussions_active?
            next issue_or_discussion
          end
        end
      end
    end

    # Returns true if reference authorization checks are run at the end of a pipeline execution using
    # the GitHub::Goomba::Reference filters.  If false, authorization checks happen in this filter and are
    # not deferred to later steps in a pipeline run.
    def deferred_authorization_checks_enabled?
      # false by default, overridden in IssueMentionFilter sub-classes
      # which use deferred authorization checks
      false
    end

    private

    # Internal: Retrieves and updates the existing issue reference or creates a new one for the given
    #   repo identifier and issue number combination. References are cached in the "scratch" hash
    #   shared between all filters in the pipeline instance.
    #
    # owner_or_nwo - a string name with owner representing the repo.
    # number - an issue/PR number
    # issue - the Issue corresponding to the number, to be cached
    #
    # Returns a Promise that rezolves into an IssueReference
    def add_issue_reference(owner_or_nwo, number, issue)
      if existing_reference = issue_reference(owner_or_nwo, number)
        existing_reference
      elsif issue.repository
        reference = GitHub::HTML::IssueReference.new(issue, "")
        key = [owner_or_nwo, number]
        scratch[:issue_references][key] = reference
        issue_mentions << reference
        reference
      end
    end

    # Internal: Retrieves and updates the existing discussion reference or creates a new one for the given
    #   repo identifier and discussion number combination. References are cached in the "scratch" hash
    #   shared between all filters in the pipeline instance.
    #
    # owner_or_nwo - a string name with owner representing the repo.
    # number - an discussion number
    # discussion - the Discussion corresponding to the number, to be cached
    #
    # Returns a DiscussionReference
    def add_discussion_reference(owner_or_nwo, number, discussion)
      if existing_reference = discussion_reference(owner_or_nwo, number)
        existing_reference
      elsif discussion.repository
        reference = GitHub::HTML::DiscussionReference.new(discussion)
        key = [owner_or_nwo, number]
        scratch[:discussion_references][key] = reference
        discussion_mentions << reference
        reference
      end
    end

    def issue_reference(owner_or_nwo, number)
      key = [owner_or_nwo, number.to_i]
      scratch[:issue_references][key]
    end

    def discussion_reference(owner_or_nwo, number)
      key = [owner_or_nwo, number.to_i]
      scratch[:discussion_references][key]
    end

    def issue_references
      scratch[:issue_references].values
    end

    def discussion_references
      scratch[:discussion_references].values
    end

    def async_load_installation_for_source_repo(repository)
      async_load_installation(repository)
    end

    def async_load_installation_for_target_repo(repository)
      Promise.resolve(false)
    end
  end
end
