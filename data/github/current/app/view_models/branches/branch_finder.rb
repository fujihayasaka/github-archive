# typed: true
# frozen_string_literal: true

require "set"

module Branches
  class BranchFinder
    extend T::Sig

    include Repos::CodeViewHelper
    include Repositories::Domain::Provider

    STALE_BRANCH_THRESHOLD = 3.months

    attr_accessor :repository, :current_user, :query, :limit

    def initialize(repository, current_user, query: nil, limit: nil, page: nil, branches_being_renamed: nil)
      @repository = repository
      @current_user = current_user
      @query = query
      @limit = limit
      @page = [page.to_i, 1].max
      @branches_being_renamed = branches_being_renamed
    end

    def default_branch
      return @default_branch if defined? @default_branch

      if react_branches_enabled?
        # optimistically look for your branches in the RefPush table
        push = RefPush.where(repository: repository)
          .where(ref: "refs/heads/#{repository.default_branch}")
          .order(pushed_at: :desc)
          .first

        if push
          ref = Git::Ref.new(repository, push.ref, push.after)
          @default_branch = Branch.new(ref, push.pushed_at.to_fs(:rfc822), push.pusher)
        end

        # if we found any RefPush records, use them
        return @default_branch if @default_branch.present? || RefPush.exists?(repository: repository)
      end

      prefill_ref_pushes

      @default_branch ||= begin
        default_ref = repository.refs.find(repository.default_branch)
        branches_by_committer_date.detect { |b| b.ref.name.b == default_ref.name.b }
      end
    end

    def page_offset
      limit ? (@page - 1) * limit : 0
    end

    # We need to limit how many rows we want to cursor through to protect us
    # from DoS-ing ourselves here. 50k feels like a nice magic number, given
    # that we spend ~5ms in your_branches per 1,000 rows we need to look at.
    YOUR_BRANCHES_CURSOR_LIMIT = 50_000

    # We're defining 'ownership' of a branch as ones the user has ever pushed
    # to, except the repository's default branch.
    def your_branches
      return limit_enum([]) unless current_user
      return @your_branches if defined? @your_branches

      if react_branches_enabled?
        # optimistically look for your branches in the RefPush table
        @your_branches = load_ref_pushes(pusher: current_user)

        # if we found any RefPush records, use them
        return @your_branches if @your_branches.any? || RefPush.exists?(repository: repository)
      end

      prefill_ref_pushes

      GitHub.dogstats.distribution_time("branch_finder.your_branches.pushes_query") do
        branch_index = branches_by_committer_date.index_by { |b| b.ref.qualified_name }
        existing_refs = Set.new(branch_index.keys)

        pushes_enum = enumerate_pushes.take(YOUR_BRANCHES_CURSOR_LIMIT).select do |push|
          # ensure we don't duplicate branch names:
          existing_refs.delete?(push.ref)
        end.map do |push|
          branch_index.fetch(push.ref)
        end

        # pushes_enum is a lazy enumerator. No queries will be executed until limit_enum is called,
        # at which time "limit" number of entries will be fetched from the enumerator.
        @your_branches = limit_enum(pushes_enum)
      end
    end

    def all_branches(include_default_branch: false)
      return @all_branches if defined? @all_branches

      if react_branches_enabled?
        # optimistically look for all branches in the RefPush table
        @all_branches = load_ref_pushes(exclude_default_branch: !include_default_branch)

        # if we found any RefPush records, use them
        return @all_branches if @all_branches.any? || RefPush.exists?(repository: repository)
      end

      prefill_ref_pushes

      branches = non_default_branches_by_committer_date.reverse
      branches = branches.unshift(default_branch) if include_default_branch

      @all_branches = limit_enum(branches)
    end

    def active_branches
      return @active_branches if defined? @active_branches

      if react_branches_enabled?
        # optimistically look for all branches in the RefPush table
        @active_branches = load_ref_pushes(after: (STALE_BRANCH_THRESHOLD + 1.in_milliseconds).ago)

        # if we found any RefPush records, use them
        return @active_branches if @active_branches.any? || RefPush.exists?(repository: repository)
      end

      prefill_ref_pushes

      @active_branches = begin
        min_date = STALE_BRANCH_THRESHOLD.ago
        limit_enum(non_default_branches_by_committer_date.reverse_each.lazy.take_while do |branch|
          branch.committer_date > min_date
        end)
      end
    end

    def stale_branches
      return @stale_branches if defined? @stale_branches

      if react_branches_enabled?
        # optimistically look for all branches in the RefPush table
        @stale_branches = load_ref_pushes(before: STALE_BRANCH_THRESHOLD.ago, order_pushed_at_desc: false)

        # if we found any RefPush records, use them
        return @stale_branches if @stale_branches.any? || RefPush.exists?(repository: repository)
      end

      prefill_ref_pushes

      @stale_branches = begin
        max_date = STALE_BRANCH_THRESHOLD.ago
        limit_enum(non_default_branches_by_committer_date.lazy.take_while do |branch|
          branch.committer_date <= max_date
        end)
      end
    end

    def query_branches
      return @query_branches if defined? @query_branches

      lowercase_query = query.b.downcase

      prefill_ref_pushes

      @query_branches = begin
        limit_enum(branches_by_committer_date.reverse_each.lazy.select do |branch|
          branch.ref.name.b.downcase.include?(lowercase_query)
        end)
      end
    end

    def non_default_branches_by_committer_date
      @non_default_branches_by_committer_date ||=
        branches_by_committer_date.reject { |b| b.ref == default_branch&.ref }
    end

    Branch = Struct.new(:ref, :committer_date_string, :author) do
      def committer_date
        @committer_date ||= Time.rfc2822(committer_date_string)
      rescue ArgumentError
        # Invalid committer date string (e.g. "Sun, 7 Feb 2106 06:28:56 -40643156")
        Time.now
      end
    end

    def branches_by_committer_date
      @branches_by_committer_date ||= begin
        repository.refs.to_a # force refs to all load to avoid loading each individually
        raw_branch_names_and_dates.map do |line|
          date, ref_name = line
          if ref = repository.refs.find_all([ref_name.b]).first
            Branch.new(ref, date, nil)
          else
            # Filter out refs that may have been returned from for-each-ref
            # but aren't in the GitRPC refs cache yet.
          end
        end.compact
      end
    end

    # Public: Returns an Array of Arrays like `["Mon, 29 Oct 2007 00:27:29 -0700", "refs/heads/mojombo"]`.
    def raw_branch_names_and_dates
      dates_and_names = repository.rpc.raw_branch_names_and_dates
      if branches_being_renamed.empty?
        return dates_and_names
      end

      dates_and_names.reject do |date_and_name|
        date, ref_name = date_and_name
        branch_name = ref_name.split("refs/heads/").last

        # Note: this might be a problem. Comparing fully qualified names (repo.default_branch) to unqualified names (branch_name)
        # leads to problems with refs/heads/refs/heads/foo and refs/heads/foo
        # Exclude branches being renamed, unless it is the default branch. The branches page requires the default branch to load.
        branches_being_renamed.include?(branch_name) && (branch_name != repository.default_branch.b)
      end
    end

    # Quacks somewhat like a WillPaginate::Collection, but doesn't know
    # `total_entries` nor `total_pages` count.
    class PaginatedCollection < Array
      attr_reader :current_page, :per_page, :has_more

      def self.create(page, per_page)
        new(page, per_page).replace yield
      end

      def initialize(page, per_page)
        @current_page = page
        @per_page = per_page
        @has_more = false
      end

      def replace(ary)
        if per_page && ary.size > per_page
          ary = ary.slice(0, per_page)
          @has_more = true
        end
        super(ary)
      end

      def previous_page
        current_page - 1 if current_page > 1
      end

      def next_page
        current_page + 1 if @has_more
      end

      # Preserve pagination info on map
      def map
        return to_enum(T.must(__method__)) unless block_given?
        dup.replace super
      end
    end

    private

    def branches_being_renamed
      @branches_being_renamed ||= repository.branches_being_renamed
    end

    def limit_enum(enum, skip = page_offset)
      PaginatedCollection.create(@page, limit) do
        if skip > 0
          since_beginning = enum.first(skip + limit + 1)
          since_beginning.slice(skip..-1) || []
        elsif limit
          enum.first(limit + 1)
        else
          enum.to_a
        end
      end
    end

    def prefill_ref_pushes
      # if no RefPushes exist yet, queue the sync job to populate the table for this repo
      RefPushBackfillJob.perform_later(repository.id) unless RefPush.exists?(repository: repository)
    end

    sig do
      params(
        search: T.nilable(String),
        pusher: T.nilable(User),
        exclude_default_branch: T.nilable(T::Boolean),
        before: T.nilable(Time),
        after: T.nilable(Time),
        order_pushed_at_desc: T.nilable(T::Boolean),
      ).returns(T::Array[Branch])
    end
    def load_ref_pushes(search: nil, pusher: nil, exclude_default_branch: true, before: nil, after: nil, order_pushed_at_desc: true)
      ##
      # The ref_pushes stores a unique record per ref, pusher combo. This results in multiple entries for a
      # given ref if there are multiple contributors. To account for this, we use two separate queries. The first for
      # retrieving the pushes for a specific pusher and a second for retrieval across all pushers.
      #
      if pusher.present?
        ##
        # This subquery finds the most recent pushed_at for any refs that a specific pusher has contributed to. This is done
        # to limit the amount of records that MySQL is required to loop through. We apply the search parameters to further reduce this result set.
        #
        subquery = RefPush.select(:repository_id, :ref, "MAX(GREATEST(COALESCE(more_recent_ref_pushes.pushed_at, ref_pushes.pushed_at), ref_pushes.pushed_at)) AS pushed_at")
        subquery = subquery.joins("LEFT JOIN ref_pushes AS more_recent_ref_pushes ON ref_pushes.repository_id = more_recent_ref_pushes.repository_id AND ref_pushes.ref = more_recent_ref_pushes.ref AND ref_pushes.pushed_at < more_recent_ref_pushes.pushed_at")
        subquery = subquery.where(repository: repository)
        subquery = subquery.where("ref LIKE ?", "refs/heads/%#{search}%") if search.present?
        subquery = subquery.where.not(ref: "refs/heads/#{repository.default_branch}") if exclude_default_branch
        subquery = subquery.where(pusher: pusher)
        subquery = subquery.group(:repository_id, :ref)

        query = RefPush.joins("INNER JOIN (#{subquery.to_sql}) AS pusher_pushes ON ref_pushes.repository_id = pusher_pushes.repository_id AND ref_pushes.ref = pusher_pushes.ref AND ref_pushes.pushed_at = pusher_pushes.pushed_at")
        query = query.where("ref_pushes.pushed_at < ?", before) if before.present?
        query = query.where("ref_pushes.pushed_at > ?", after) if after.present?
      else
        ##
        # We find the most recent pushes by comparing against other similar pushes to the same refs. If there aren't any or there
        # are no other refs with more recent pushed_at values, then the push is guaranteed to be the most recent.
        #
        query = RefPush.from("ref_pushes USE INDEX(index_ref_pushes_on_repository_id_and_ref_and_pusher_id)").where(repository: repository)

        # find the latest push for each ref
        if repository.feature_enabled?(:ref_push_group_max)
          query = query.group(:ref).having("MAX(pushed_at) = pushed_at")
        else
          query = query.joins("LEFT JOIN ref_pushes older_ref_pushes USE INDEX(index_ref_pushes_on_repository_id_and_ref_and_pusher_id) ON ref_pushes.repository_id = older_ref_pushes.repository_id AND ref_pushes.ref = older_ref_pushes.ref AND ref_pushes.pushed_at < older_ref_pushes.pushed_at")
          query = query.where("older_ref_pushes.pushed_at IS NULL")
        end

        query = query.where("ref_pushes.ref LIKE ?", "refs/heads/%#{search}%") if search.present?
        query = query.where.not(ref: "refs/heads/#{repository.default_branch}") if exclude_default_branch
        query = query.where("ref_pushes.pushed_at < ?", before) if before.present?
        query = query.where("ref_pushes.pushed_at > ?", after) if after.present?
      end

      if !exclude_default_branch
        prefixed_default_branch = "refs/heads/#{ActiveRecord::Base.sanitize_sql(repository.default_branch)}"
        query = query.order(Arel.sql(<<-SQL, default_branch: prefixed_default_branch))
          CASE ref_pushes.ref WHEN :default_branch THEN 0 ELSE 1 END
        SQL
      end

      query = query.order(pushed_at: order_pushed_at_desc ? :desc : :asc)

      pushes = limit_enum(query)
      GitHub::PrefillAssociations.prefill_associations(pushes, [:pusher])

      pushes.map do |push|
        ref = Git::Ref.new(repository, push.ref, push.after)
        Branch.new(ref, push.pushed_at.to_fs(:rfc822), push.pusher)
      end
    end

    def enumerate_pushes(&block)
      return enum_for(:enumerate_pushes).lazy unless block_given?

      chunk_size = 100
      pagination = GH::Pagination::Cursor.new(first: chunk_size)

      pushes = repositories_domain.pushes.by_user(repository_id: repository.id, pusher_id: current_user.id, exclude_ref: default_branch&.ref&.qualified_name, pagination:)
      pushes.each(&block)

      while pushes.count == chunk_size
        pagination = GH::Pagination::Cursor.new(after: pushes.end_cursor, first: chunk_size)
        pushes = repositories_domain.pushes.by_user(repository_id: repository.id, pusher_id: current_user.id, exclude_ref: default_branch&.ref&.qualified_name, pagination:)
        pushes.each(&block)
      end
    end
  end
end
