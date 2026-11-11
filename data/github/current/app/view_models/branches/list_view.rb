# typed: false
# frozen_string_literal: true

module Branches
  class ListView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :repository
    attr_reader :search_query

    def initialize(*)
      super

      eager_load!
    end

    def template_name
      raise NotImplementedError
    end

    def search_mode?
      search_query.present?
    end

    def all_branches
      raise NotImplementedError
    end

    def can_push?
      return @can_push if defined?(@can_push)

      @can_push = logged_in? && repository.pushable_by?(current_user)
    end

    def nav_link(label, view_name, options)
      options = options.dup
      options[:class] ||= ""
      options[:class] += " selected" if view_name == selected_view

      helpers.link_to label,
        urls.branches_path(repository, view: view_name),
        options
    end

    def search_path
      urls.branches_path(repository, view: :all)
    end

    private

    attr_reader :head_commits, :author_email_map, :pull_requests, :branch_has_open_pull_as_base

    # Private: All the branch names that are currently in the process of changing.
    #
    # Returns an Array of Strings.
    def branches_being_renamed
      @branches_being_renamed ||= repository.branches_being_renamed
    end

    # Private: Is the given branch in the process of being renamed?
    #
    # branch - String branch name
    #
    # Returns a Boolean.
    def branch_being_renamed?(branch)
      if !branch.is_a?(String) && (Rails.env.development? || Rails.env.test?)
        raise "expected String branch name, got #{branch.class.name}"
      end
      branches_being_renamed.include?(branch)
    end

    # Private: All the branch names that someone attempted to rename but where the
    # rename process hit an error.
    #
    # Returns a Hash of string branch name => RepositoryBranchRename.
    def recently_errored_branch_renames
      @recently_errored_branch_renames ||= repository.
        recently_errored_branch_renames.index_by(&:old_name)
    end

    def recent_errored_branch_rename_for(branch)
      if !branch.is_a?(String) && (Rails.env.development? || Rails.env.test?)
        raise "expected String branch name, got #{branch.class.name}"
      end
      recently_errored_branch_renames[branch]
    end

    def eager_load!
      branches = all_branches
      branches = branches.compact
      @head_commits = load_head_commits(branches)
      @author_email_map = load_authors(head_commits.values)
      Promise.all(head_commits.values.map(&:async_has_status_check_rollup?)).sync
      @pull_requests = load_pull_requests(branches)
    end

    def base_branch
      @base_branch ||= begin
        name = repository.heads.find(repository.default_branch).name
        if b = head_commits[name.b]
          b.oid
        else
          repository.heads.find(name.b).sha
        end
      end
    end

    def load_head_commits(branches)
      refs = branches.map(&:ref)
      head_commits_by_sha = repository.commits.find(refs.map(&:sha)).index_by(&:sha)
      Hash[refs.map { |ref| [ref.ref, head_commits_by_sha[ref.sha]] }]
    end

    def load_authors(commits)
      emails = commits.map(&:author_email).uniq
      emails = emails.reject { |email| UserEmail.generic_domain?(email) }

      # Emu specific processing
      if repository && repository.is_enterprise_managed?
        @enterprise_managed_business = repository.enterprise_managed_business
        emails = @enterprise_managed_business.add_emu_shortcode_to_emails(emails)
      end

      business = repository.enterprise_managed_business if repository.is_enterprise_managed?
      User.find_by_emails(emails, business: business)
    end

    def load_pull_requests(branches)
      PullRequest.
        includes(:issue).
        where(
          head_repository_id: repository.id,
          base_repository_id: repository.id,
          head_ref: branches.map { |branch| branch.ref.name }
        ).select do |pull|
          pull.head_sha == head_commits[pull.head_ref].oid
        end.index_by do |pull|
          pull.head_ref
        end
    end

    # Private: Get a list of view models for rendering the given branches.
    #
    # branches - an Array of Branches::BranchFinder::Branch instances
    # page_section - a String or Symbol uniquely identifying the section on the page where
    #                these branches will be shown; used to generate unique DOM IDs for
    #                form elements since the same branch might be in several sections
    #                of the page
    #
    # Returns a PaginatedCollection of Branches::BranchView instances.
    def create_item_views(branches, page_section: :none)
      branches = branches.map do |branch|
        if branch != nil
          branch
        end
      end
      GitHub::PrefillAssociations.prefill_batch_method(branches.map(&:ref), :policy_evaluator)
      branches.map { |branch| create_item_view(branch, page_section: page_section) }
    end

    # Private: Get a view model for rendering the given branch.
    #
    # branch - a Branches::BranchFinder::Branch
    # page_section - a String or Symbol uniquely identifying the section on the page where
    #                the branch will be shown; used to generate unique DOM IDs for
    #                form elements since the same branch might be in several sections
    #                of the page
    #
    # Returns a Branches::BranchView.
    def create_item_view(branch, page_section: :none)
      ref = branch.ref
      name = ref.name
      commit = head_commits.fetch(name)

      email = commit.author_email
      if email && @enterprise_managed_business
        email = @enterprise_managed_business.add_emu_shortcode_to_emails(email)
      end

      user = author_email_map.fetch(email, nil)
      pull = pull_requests.fetch(name, nil)

      BranchView.new(
        ref: ref,
        commit: commit,
        base_commit: base_branch,
        user: user,
        repository: repository,
        pull_request: pull,
        can_push: can_push?,
        current_user: current_user,
        is_being_renamed: branch_being_renamed?(name),
        page_section: page_section,
        recent_errored_rename: recent_errored_branch_rename_for(name),
        is_branch_protected: ref.protected?
      )
    end
  end
end
