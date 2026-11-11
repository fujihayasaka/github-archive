# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# Backfills the oauth_enterprise_limits table for existing OAuth app tokens.
#
# For each distinct (application_id, user_id) pair in oauth_accesses where
# the token belongs to a real OAuth application (not a PAT), this transition
# computes the GHEC higher rate limit eligibility and writes the result.
#
# The table is on the authnd cluster and is read by authnd during token
# enrichment to populate IET gateway attributes.
#
# Usage:
#   script/transition backfill-oauth-enterprise-limits [--write] [--verbose]
module GitHub
  module Transitions
    class BackfillOauthEnterpriseLimits < Base
      ORG_BATCH_SIZE = 500

      # Lightweight AR model for iterating over oauth_accesses by primary key.
      class OauthAccessRow < ApplicationRecord::Domain::Integrations
        self.table_name = "oauth_accesses"
      end

      # Standalone AR model for the target table (authnd cluster).
      # Duplicated from OauthEnterpriseLimit to keep this transition
      # self-contained per transition best practices.
      class OauthEnterpriseLimitRow < ApplicationRecord::Domain::Authentication
        self.table_name = "oauth_enterprise_limits"

        sig do
          params(
            app_id: Integer,
            user_id: Integer,
            request_owner_id: Integer,
          ).void
        end
        def self.upsert_limit(app_id:, user_id:, request_owner_id:)
          upsert(
            { app_id:, user_id:, request_owner_id:, higher_limit_eligible: true },
          )
        end
      end

      iterate_over :database_table, params: {
        model_class: OauthAccessRow,
        columns: %i[application_id user_id],
        conditions: "application_type = 'OauthApplication' AND application_id != 0",
      }

      sig { override.void }
      def after_initialize
        @processed = T.let(0, T.nilable(Integer))
        @skipped = T.let(0, T.nilable(Integer))
        @written = T.let(0, T.nilable(Integer))
      end

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        # Deduplicate by (app_id, user_id) since multiple tokens can exist
        # for the same pair.
        pairs = T.let({}, T::Hash[String, [Integer, Integer]])
        items.each do |_id, values|
          app_id = T.cast(values[:application_id], Integer)
          user_id = T.cast(values[:user_id], Integer)
          key = "#{app_id}:#{user_id}"
          pairs[key] ||= [app_id, user_id]
        end

        pairs.each_value do |app_id, user_id|
          @processed = T.must(@processed) + 1

          app = OauthApplication.find_by(id: app_id)
          user = T.cast(Users.domain.by_id(user_id), T.nilable(User))

          if app.nil? || user.nil?
            @skipped = T.must(@skipped) + 1
            next
          end

          request_owner, higher_limit = compute_request_owner(app:, user:)

          if request_owner.nil? || !higher_limit
            @skipped = T.must(@skipped) + 1
            next
          end

          if dry_run?
            log "Would write limit for app_id=#{app_id} user_id=#{user_id} " \
                "request_owner_id=#{request_owner.id} higher_limit=#{higher_limit}" if verbose?
          else
            write_to(model_class: OauthEnterpriseLimitRow) do
              OauthEnterpriseLimitRow.upsert_limit(
                app_id:,
                user_id:,
                request_owner_id: request_owner.id,
              )
            end
            @written = T.must(@written) + 1
          end
        end

        log "Progress: processed=#{@processed} written=#{@written} skipped=#{@skipped}"
      end

      private

      # Compute request owner following the OAuth branch of Api::RequestOwner.call.
      # Duplicated from OauthEnterpriseLimitWriter to keep this transition
      # self-contained per transition best practices.
      #
      # Priority:
      # 1. App owner is in user's orgs → app owner
      # 2. OauthApplicationApproval for user's org → prefer GHEC-qualified org
      # 3. No match → nil
      sig { params(app: OauthApplication, user: User).returns([T.nilable(T.any(User, Organization)), T::Boolean]) }
      def compute_request_owner(app:, user:)
        app_owner = app.user
        return [nil, false] if app_owner.nil?

        # Priority 1: app owner is one of user's orgs
        org_ids = user.organization_ids
        if org_ids.include?(app_owner.id)
          higher_limit = Api::RateLimitConfiguration.qualifies_for_higher_limit?(app_owner)
          return [app_owner, higher_limit]
        end

        # Priority 2: check OauthApplicationApproval for user's orgs (batched to
        # avoid unbounded IN clauses for users with many org memberships).
        # NOTE: We intentionally filter to approved state only, unlike Api::RequestOwner
        # (app/api/request_owner.rb:30) which includes all states. That is a bug — see #426076.
        org_ids.each_slice(ORG_BATCH_SIZE) do |batch|
          OauthApplicationApproval
            .approved
            .includes(:organization)
            .where(organization_id: batch, application_id: app.id)
            .each do |approval|
              if Api::RateLimitConfiguration.qualifies_for_higher_limit?(approval.organization)
                return [approval.organization, true]
              end
            end
        end

        # Priority 3: no match
        [nil, false]
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::BackfillOauthEnterpriseLimits.new(args).run
end
