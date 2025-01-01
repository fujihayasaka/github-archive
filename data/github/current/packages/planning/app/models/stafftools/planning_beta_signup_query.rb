# typed: true
# frozen_string_literal: true

module Stafftools
  # A custom query class to run decomposed SQL queries across multipls database
  # domains for the purpose of sorting PVD waitlist signups in stafftools.
  class PlanningBetaSignupQuery
    include GitHub::Memoizer

    DEFAULT_SORT = "created_at"
    DEFAULT_SORT_ORDER = "asc"
    PAGE_SIZE = 100

    attr_reader :base_query, :member_metadata, :page, :search, :sort, :order

    def initialize(page: 1, search: nil, base_query: ProjectsTasklistsBeta.new.waitlist)
      @base_query = base_query
      @page = page.to_i < 1 ? 1 : page.to_i
      @search = search&.strip
      @sort = DEFAULT_SORT
      @order = DEFAULT_SORT_ORDER
      @member_metadata = {}
    end

    memoize def memberships
      membership_query = default_query.preload(:member, :actor).paginate(page: page, per_page: PAGE_SIZE)

      # Load/update org metadata for display in the signup table
      org_ids = membership_query.pluck(:member_id)

      update_member_metadata(org_ids)

      membership_query
    end

    private

    # When we don't need to cross database domain boundaries we can just do a
    # normal ActiveRecord search
    def default_query
      query = base_query.order("early_access_memberships.#{DEFAULT_SORT} #{order}")

      if search.present?
        query = query.with_member_login(search)
      end

      query
    end

    # Load metadata for a set of orgs
    def update_member_metadata(org_ids)
      update_member_metadata_hash(:member_count, org_ids)
      update_member_metadata_hash(:plan, org_ids)
    end

    # Load a particular type of metadata for a set of orgs
    #
    # Note: When we're dealing with a custom sort this will first get called
    # with a superset of org ids before being called a second time with the
    # subset of org IDs that appear in the final query results, at which point
    # we'll prune what we no longer need. In the case of the default query this
    # will only get called once with the subset of org IDs that appear in the
    # final query results.
    def update_member_metadata_hash(type, org_ids)
      if member_metadata[type] && member_metadata[type].any?
        # Remove any org_id keys we no longer need
        member_metadata[type].delete_if { |k, _| !org_ids.include?(k) }
        remaining_keys = org_ids - member_metadata[type].keys
        return unless remaining_keys.any?

        # Backfill any remaining org_ids - this should never be the case but I
        # added it as a precaution.
        if type == :member_count
          member_metadata[:member_count].merge!(send(
            :member_count_hash, org_ids - member_metadata[:member_count].keys
          ))
        elsif type == :plan
          member_metadata[:plan].merge!(send(
            :plan_hash, org_ids - member_metadata[:plan].keys
          ))
        end
      else
        if type == :member_count
          member_metadata[:member_count] = send(:member_count_hash, org_ids)
        elsif type == :plan
          member_metadata[:plan] = send(:plan_hash, org_ids)
        end
      end
    end

    # Get a count of the org members for a list of orgs. Returns a
    # hash with org ids as the keys and member counts as the values
    def member_count_hash(org_ids)
      organizations = ::Organization.where(id: org_ids)

      hash = organizations.each_with_object({}) do |(organization), memo|
        memo[organization.id] ||= 0
        count = organization.members.limit(::Organization::MEGA_ORG_MEMBER_THRESHOLD).size
        memo[organization.id] += count
      end

      backfill_hash(org_ids, hash)
    end

    # Fetch the plan for each organization and build up an object to return to the view
    def plan_hash(org_ids)
      organizations = ::Organization.where(id: org_ids)

      hash = organizations.each_with_object({}) do |(organization), memo|
        memo[organization.id] ||= ""
        plan = organization.plan.display_name.titleize
        memo[organization.id] += plan
      end

      backfill_hash(org_ids, hash)
    end

    # Backfill any orgs that might not have returned data from the query. We
    # prefer this over setting a default for the hash (`Hash.new(0)`) because
    # it allows us to test the metadata pruning more effectively and will help
    # us identify data processing errors in the front end (where a missing
    # metadata value will be show up as nil instead of 0)
    def backfill_hash(org_ids, hash)
      remaining_orgs = org_ids - hash.keys
      if remaining_orgs.any?
        remaining_orgs.each do |org_id|
          hash[org_id] = 0 # 0 count
        end
      end
      hash
    end
  end
end
