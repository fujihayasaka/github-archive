# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module AccountStafftoolsInfo

      include Platform::Interfaces::Base
      include Scientist

      description "Common stafftools info fields for user and organization accounts."
      visibility :internal

      field :last_ip, String, description: "The ip address for the account recorded when they last logged in.", null: true

      sig { returns(T.nilable(String)) }
      def last_ip
        @object.account.last_ip
      end

      field :ip_neighbors, Connections.define(Unions::Account), description: "The accounts that show share the same lastIp", null: true, connection: true do
        argument :prefix, Enums::NetworkPrefix, Enums::NetworkPrefix.description, default_value: 24, required: false
      end
      sig { params(prefix: Integer).returns(ActiveRecord::Relation) }
      def ip_neighbors(prefix: 24)
        ::User.by_ip_with_prefix(@object.account.last_ip, prefix: prefix)
      end

      field :ip_neighbors_count, Integer, description: "The number of accounts with the same last ip.", null: false
      sig { returns(Integer) }
      def ip_neighbors_count
        last_ip = @object.account.last_ip
        return 0 if last_ip.nil?

        cache = @context.namespace(:ip_neighbor_counts)
        cache[last_ip] ||= ::User.by_ip(last_ip).count
      end

      field :spammy_ip_neighbors_count, Integer, description: "The number of spammy accounts with the same last ip.", null: false
      sig { returns(Integer) }
      def spammy_ip_neighbors_count
        last_ip = @object.account.last_ip
        return 0 if last_ip.nil?

        cache = @context.namespace(:spammy_ip_neighbor_counts)
        cache[last_ip] ||= ::User.spammy.by_ip(last_ip).count
      end

      field :network_address32_reputation, Objects::SpamuraiReputation, description: "IP address reputation.", null: true
      sig { returns(T.nilable(Spam::Reputation)) }
      def network_address32_reputation
        last_ip = @object.account.last_ip
        return if last_ip.nil?

        prefix = 32
        cache = @context.namespace(:network_address_32_counts)
        cache[last_ip] ||= {
          sample_size: ::User.by_ip_with_prefix(last_ip, prefix: prefix).count,
          not_spammy_sample_size: T.unsafe(::User.not_spammy).by_ip_with_prefix(last_ip, prefix: prefix).count,
        }

        Spam::Reputation.generate(
          sample_size: cache[last_ip][:sample_size],
          not_spammy_sample_size: cache[last_ip][:not_spammy_sample_size]
        )
      end

      field :network_address24_reputation, Objects::SpamuraiReputation, description: "Class C reputation.", null: true
      sig { returns(T.nilable(Spam::Reputation)) }
      def network_address24_reputation
        last_ip = @object.account.last_ip
        return if last_ip.nil?

        prefix = 24
        cache = @context.namespace(:network_address_24_counts)
        cache[last_ip] ||= {
          sample_size: ::User.by_ip_with_prefix(last_ip, prefix: prefix).count,
          not_spammy_sample_size: T.unsafe(::User.not_spammy).by_ip_with_prefix(last_ip, prefix: prefix).count,
        }

        Spam::Reputation.generate(
          sample_size: cache[last_ip][:sample_size],
          not_spammy_sample_size: cache[last_ip][:not_spammy_sample_size]
        )
      end

      field :is_spammy, Boolean, description: "Is the account spammy.", null: false
      sig { returns(T::Boolean) }
      def is_spammy
        @object.account.spammy?
      end

      field :spammy_reason, String, description: "The spammy reason.", null: true
      sig { returns(T.nilable(String)) }
      def spammy_reason
        @object.account.spammy_reason
      end

      field :is_hammy, Boolean, description: "Is the account hammy.", null: false
      sig { returns(T::Boolean) }
      def is_hammy
        @object.account.hammy?
      end

      field :is_never_spammy, Boolean, description: "Can this account be marked as spammy.", null: false
      sig { returns(T::Boolean) }
      def is_never_spammy
        @object.account.never_spammy?
      end

      field :is_suspended, Boolean, description: "Is the account suspended.", null: false
      sig { returns(T::Boolean) }
      def is_suspended
        @object.account.suspended?
      end

      field :has_paid_plan, Boolean, description: "Does account have a paid plan.", null: false
      sig { returns(Promise[T::Boolean]) }
      def has_paid_plan
        @object.account.async_paid_plan?
      end

      field :has_sponsored_via_patreon, Boolean, description: "Has the account ever connected their GitHub " \
        "account to a Patreon account and paid for a sponsorship on GitHub via Patreon.", null: false
      sig { returns Promise[T::Boolean] }
      def has_sponsored_via_patreon
        Loaders::HasSponsoredViaPatreon.load(@object.account.id).then do |result|
          result.nil? ? false : result
        end
      end

      field :is_gift_account, Boolean, description: "Is the account classified as a gift account.", null: false
      sig { returns(T::Boolean) }
      def is_gift_account
        @object.account.gift?
      end

      field :has_blacklisted_payment_method, Boolean, description: "Does the account have a blacklisted payment method.", null: false
      sig { returns(T::Boolean) }
      def has_blacklisted_payment_method
        BlacklistedPaymentMethod.where(user_id: @object.account.id).exists?
      end

      field :accounts_with_same_payment_method, [Unions::Account], description: "Accounts with the same payment method.", null: true do
        argument :limit, Int, "Optional number to limit the accounts returned, defaults to 5", default_value: 5, required: false
      end
      sig { params(limit: Integer).returns(T::Array[::User]) }
      def accounts_with_same_payment_method(limit:)
        payment_unique_number_identifier = PaymentMethod.where(user_id: @object.account.id).first&.unique_number_identifier
        if payment_unique_number_identifier
          payment_methods = PaymentMethod.where("unique_number_identifier = ?", payment_unique_number_identifier)
            .limit(limit)
            .includes(:user)
          users = payment_methods.map(&:user)
          # Remove nil from the array to cover cases like payment methods for a Business
          # where the PaymentMethod#user is nil.
          users.compact
        else
          []
        end
      end

      field :stripe_fraud_warnings, [Objects::StripeEarlyFraudWarning], description: "Stripe's early fraud warnings", null: true do
        argument :charge_limit, Int, "Number to limit the number of charges associated to an account that will be used to search for early fraud warnings, defaults to 20, maximum 100", default_value: 20, required: false
      end
      sig { params(charge_limit: Integer).returns(T::Array[Stripe::Radar::EarlyFraudWarning]) }
      def stripe_fraud_warnings(charge_limit:)
        if charge_limit > 100
          raise Platform::Errors::NotImplemented.new("Limits above 100 requires pagination and is not yet supported")
        end

        unique_number_identifier = PaymentMethod.where(user_id: @object.account.id).first&.unique_number_identifier
        return [] unless unique_number_identifier

        charges = Stripe::Charge.search(
          { query: "payment_method_details.card.fingerprint:\"#{unique_number_identifier}\"", limit: charge_limit },
          # Stripe version "2020-08-27" or later is required for this call to work
          { stripe_version: "2020-08-27" }
        )
        charge_ids = charges[:data].map { |charge| charge["id"] }

        early_frauds = []
        charge_ids.each do |charge_id|
          early_fraud = Stripe::Radar::EarlyFraudWarning.list({ charge: charge_id })[:data]
          unless early_fraud.empty?
            early_frauds.concat(early_fraud)
          end
        end
        early_frauds
      rescue Stripe::InvalidRequestError => e
        raise Platform::Errors::NotFound.new(e.message)
      rescue Stripe::APIConnectionError
        raise Platform::Errors::ServiceUnavailable.new("Stripe is currently unavailable. Please try again later.")
      end

      field :has_matching_last_ip_spam_pattern, Boolean, description: "Account has matching spam pattern on last ip.", null: false
      sig { returns(T::Boolean) }
      def has_matching_last_ip_spam_pattern
        account = @object.account
        return false if account.last_ip.nil?

        @context[:last_ip_spam_patterns_regexp] ||= SpamPattern.last_ip_patterns_regexp

        @context[:last_ip_spam_patterns_regexp].match?(account.last_ip)
      end

      field :has_newer_non_spammy_ip_neighbor, Boolean, description: "Account has newer non-spammy ip neighbor.", null: false
      sig { returns(T::Boolean) }
      def has_newer_non_spammy_ip_neighbor
        account = @object.account
        return false if account.last_ip.nil?
        ::User.not_spammy.by_ip(account.last_ip).where("id > ?", account.id).exists?
      end

      field :lfs_repositories, Connections::Repository, description: "The repositories for this account that have LFS objects.", null: false, connection: true
      sig { returns(Promise[T::Array[::Repository]]) }
      def lfs_repositories
        Loaders::LfsRepositories.load(@object.account.id).then do |repos|
          ArrayWrapper.new(repos.sort_by(&:id))
        end
      end

      field :lfs_networks_by_usage, Connections::Repository, description: "The networks for this account that have LFS usage, .", null: true, connection: true
      sig { returns(Promise[T::Array[::Repository]]) }
      def lfs_networks_by_usage
        Loaders::LfsNetworksByUsage.load(@object.account.id)
      end

      field :time_zone, String, description: "The account time zone.", null: true
      sig { returns(T.nilable(ActiveSupport::TimeZone)) }
      def time_zone
        ActiveSupport::TimeZone[@object.account.time_zone_name.to_s]
      end

      field :staff_notes, Connections.define(Objects::StaffNote), "Staff notes for account.",
        null: true, connection: true
      sig { returns(Promise[T::Array[::StaffNote]]) }
      def staff_notes
        @object.account.async_staff_notes.then do |notes|
          ArrayWrapper.new(notes)
        end
      end

      field :pinned_staff_note, Objects::StaffNote, "Pinned staff note for account.", null: true
      sig { returns(T.nilable(::StaffNote)) }
      def pinned_staff_note
        StaffNote.where(notable: @object.account, is_pinned: true)
          .limit_execution_time(limit_ms: 2000)
          .first
      rescue ActiveRecord::StatementTimeout
      end

      field :profile, Objects::Profile, "Account profile.", null: true
      sig { returns(Promise[T.nilable(Profile)]) }
      def profile
        @object.account.async_profile
      end

      field :is_trade_restricted, Boolean, description: "Indicates if the account is subject to trade restrictions.", null: false
      sig { returns(T::Boolean) }
      def is_trade_restricted
        @object.account.has_any_trade_restrictions?
      end

      field :trade_controls_restriction, String, description: "Account's trade controls restriction type", null: false
      sig { returns(Promise[T.nilable(String)]) }
      def trade_controls_restriction
        async_trade_controls_restriction.then(&:type)
      end

      field :trade_controls_enforcement_reason, String, description: "Account's trade controls restriction reason", null: true
      sig { returns(Promise[T.nilable(String)]) }
      def trade_controls_enforcement_reason
        async_trade_controls_restriction.then(&:enforcement_reason)
      end

      field :trade_controls_enforced_date, Scalars::DateTime, description: "Account's trade controls enforcement date", null: true
      sig { returns(Promise[T.nilable(Time)]) }
      def trade_controls_enforced_date
        async_trade_controls_restriction.then(&:last_enforcement_date)
      end

      field :trade_controls_override_date, Scalars::DateTime, description: "Account's trade controls override date", null: true
      sig { returns(Promise[T.nilable(Time)]) }
      def trade_controls_override_date
        async_trade_controls_restriction.then(&:last_override_date)
      end

      field :trade_screening_status, String, description: "Account's trade screening status", null: false
      sig { returns(Promise[T.nilable(String)]) }
      def trade_screening_status
        async_trade_screening_record.then(&:msft_trade_screening_status)
      end

      field :last_trade_screening_date, Scalars::DateTime, description: "Date and time when the account's trade screening status was last updated", null: true
      sig { returns(Promise[T.nilable(Time)]) }
      def last_trade_screening_date
        async_trade_screening_record.then(&:last_trade_screen_date)
      end

      field :trade_screening_external_id, String, description: "Account's external id used for identifying the account during trade screening", null: true
      sig { returns(Promise[T.nilable(String)]) }
      def trade_screening_external_id
        async_trade_screening_record.then(&:external_uuid)
      end

      field :has_legal_hold, Boolean, description: "Whether a user has a legal hold", null: true

      def has_legal_hold
        Loaders::ActiveRecord.load(::LegalHold, @object.account.id, column: :user_id).then(&:present?)
      end

      field :owned_repositories_count, Integer, description: "The number of repositories this account owns.", null: false do
        argument :visibility, Enums::RepositoryPrivacy, "If non-null, filters repositories according to visibility.", required: false
      end

      def owned_repositories_count(**arguments)
        if arguments[:visibility] == "private"
          @object.account.private_repositories.count
        elsif arguments[:visibility] == "public"
          @object.account.public_repositories.count
        else
          @object.account.repositories.count
        end
      end

      field :associated_repositories_count, Integer, description: "The number of repositories this account is associated with.", null: false do
        argument :affiliations, [Enums::RepositoryAffiliation, null: true],
          description: "Array of owner's affiliation options for repository count. For example, OWNER will include only repositories that the organization or user being viewed owns.",
          required: false,
          default_value: [:owned, :direct]

        argument :visibility, Enums::RepositoryPrivacy,
          description: "If non-null, filters repositories according to visibility.",
          required: false
      end

      def associated_repositories_count(affiliations:, visibility: nil)
        scope = if visibility == "private"
          ::Repository.private_scope
        elsif visibility == "public"
          ::Repository.public_scope
        else
          ::Repository
        end

        scope
          .from("repositories FORCE INDEX (PRIMARY)")
          # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
          .where(id: @object.account.associated_repository_ids(including: affiliations))
          # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
          .active
          .count
      end

      field :has_actually_paid_money, Boolean, description: "Has actually paid money to GitHub at some point.", null: false

      def has_actually_paid_money
        GitHub::SpamChecker.has_actually_paid_money?(@object.account)
      end

      field :public_projects_count, Integer, description: "Count of public projects created by user regardless of owner. Returns -1 if timed out querying for count", null: false

      def public_projects_count
        Project.where(creator: @object.account, public: true)
               .limit_execution_time(limit_ms: 2000)
               .count
      rescue ActiveRecord::StatementTimeout
        -1
      end

      field :public_project_cards_count, Integer, description: "Count of public project cards created by user regardless of owner. Returns -1 if timed out querying for count", null: false

      def public_project_cards_count
        ProjectCard.joins(:project).where(creator: @object.account, project: { public: true })
               .limit_execution_time(limit_ms: 2000)
               .count
      rescue ActiveRecord::StatementTimeout
        -1
      end

      field :last_five_public_projects, [Objects::Project], description: "The five most recently updated projects that the user created. Returns empty results if timed out querying for projects", null: false

      def last_five_public_projects
        Project.where(creator: @object.account, public: true)
               .order(updated_at: :desc)
               .limit_execution_time(limit_ms: 2000)
               .limit(5)
      rescue ActiveRecord::StatementTimeout
        []
      end

      field :last_five_public_project_cards, [Objects::ProjectCard], description: "The five most recently updated project cards that the user created. Returns empty results if timed out querying for project cards", null: false

      def last_five_public_project_cards
        ProjectCard.joins(:project)
          .where(creator: @object.account, project: { public: true })
          .order(updated_at: :desc)
          .limit_execution_time(limit_ms: 2000)
          .limit(5)
      rescue ActiveRecord::StatementTimeout
        []
      end

      field :public_projects_next_count, Integer, description: "Count of public projects (Memex/vNext) created by user regardless of owner. Returns -1 if timed out querying for count", null: false, deprecated: Helpers::ProjectNext::DeprecationNotice

      def public_projects_next_count
        MemexProject.where(creator: @object.account, public: true)
          .limit_execution_time(limit_ms: 2000)
          .count
      rescue ActiveRecord::StatementTimeout
        -1
      end

      field :public_project_next_items_count, Integer, description: "Count of public project (Memex/vNext) items created by user regardless of project owner. Returns -1 if timed out querying for count", null: false, deprecated: Helpers::ProjectNext::DeprecationNotice

      def public_project_next_items_count
        MemexProjectItem.joins(:memex_project)
          .where(creator: @object.account, memex_project: { public: true })
          .limit_execution_time(limit_ms: 2000)
          .count
      rescue ActiveRecord::StatementTimeout
        -1
      end

      field :public_project_next_item_field_values_count, Integer, description: "Count of public project (Memex/vNext) item field values created by user regardless of project owner. Returns -1 if timed out querying for count", null: false, deprecated: Helpers::ProjectNext::DeprecationNotice

      def public_project_next_item_field_values_count
        MemexProjectColumnValue.joins(memex_project_column: :memex_project)
          .where(creator: @object.account, memex_project: { public: true })
          .limit_execution_time(limit_ms: 2000)
          .count
      rescue ActiveRecord::StatementTimeout
        -1
      end

      field :last_five_public_projects_next, [Objects::ProjectNext], description: "The five most recently updated public projects (Memex/vNext) that the user created. Returns empty results if timed out querying for projects", null: false, deprecated: Helpers::ProjectNext::DeprecationNotice

      def last_five_public_projects_next
        MemexProject.where(creator: @object.account, public: true)
          .order(updated_at: :desc)
          .limit_execution_time(limit_ms: 2000)
          .limit(5)
      rescue ActiveRecord::StatementTimeout
        []
      end

      field :last_five_public_project_next_items, [Objects::ProjectNextItem], description: "The five most recently updated public project (Memex/vNext) items that the user created. Returns empty results if timed out querying for project items", null: false, deprecated: Helpers::ProjectNext::DeprecationNotice

      def last_five_public_project_next_items
        MemexProjectItem.joins(:memex_project)
          .where(creator: @object.account, memex_project: { public: true })
          .order(updated_at: :desc)
          .limit_execution_time(limit_ms: 2000)
          .limit(5)
      rescue ActiveRecord::StatementTimeout
        []
      end

      field :last_five_public_project_next_item_field_values, [Objects::ProjectNextItemFieldValue], description: "The five most recently updated public project (Memex/vNext) item field values that the user created. Returns empty results if timed out querying for project item field values", null: false, deprecated: Helpers::ProjectNext::DeprecationNotice

      def last_five_public_project_next_item_field_values
        MemexProjectColumnValue.joins(memex_project_column: :memex_project)
          .where(creator: @object.account, memex_project: { public: true })
          .order(updated_at: :desc)
          .limit_execution_time(limit_ms: 2000)
          .limit(5)
      rescue ActiveRecord::StatementTimeout
        []
      end

      field :public_projects_v2_count, Integer, description: "Count of public projects (Memex) created by user regardless of owner. Returns -1 if timed out querying for count", null: false

      def public_projects_v2_count
        MemexProject.where(creator: @object.account, public: true)
          .limit_execution_time(limit_ms: 2000)
          .count
      rescue ActiveRecord::StatementTimeout
        -1
      end

      field :public_project_v2_items_count, Integer, description: "Count of public project (Memex) items created by user regardless of project owner. Returns -1 if timed out querying for count", null: false

      def public_project_v2_items_count
        MemexProjectItem.joins(:memex_project)
          .where(creator: @object.account, memex_project: { public: true })
          .limit_execution_time(limit_ms: 2000)
          .count
      rescue ActiveRecord::StatementTimeout
        -1
      end

      field :public_project_v2_item_field_values_count, Integer, description: "Count of public project (Memex) item field values created by user regardless of project owner. Returns -1 if timed out querying for count", null: false

      def public_project_v2_item_field_values_count
        MemexProjectColumnValue.joins(memex_project_column: :memex_project)
          .where(creator: @object.account, memex_project: { public: true })
          .limit_execution_time(limit_ms: 2000)
          .count
      rescue ActiveRecord::StatementTimeout
        -1
      end

      field :last_five_public_projects_v2, [Objects::ProjectV2], description: "The five most recently updated public projects (Memex) that the user created. Returns empty results if timed out querying for projects", null: false

      def last_five_public_projects_v2
        MemexProject.where(creator: @object.account, public: true)
          .order(updated_at: :desc)
          .limit_execution_time(limit_ms: 2000)
          .limit(5)
      rescue ActiveRecord::StatementTimeout
        []
      end

      field :last_five_public_project_v2_items, [Objects::ProjectV2Item], description: "The five most recently updated public project (Memex) items that the user created. Returns empty results if timed out querying for project items", null: false

      def last_five_public_project_v2_items
        MemexProjectItem.joins(:memex_project)
          .where(creator: @object.account, memex_project: { public: true })
          .order(updated_at: :desc)
          .limit_execution_time(limit_ms: 2000)
          .limit(5)
      rescue ActiveRecord::StatementTimeout
        []
      end

      field :last_five_public_project_v2_item_field_values, [Interfaces::ProjectV2ItemFieldValueCommon], description: "The five most recently updated public project (Memex) item field values that the user created. Returns empty results if timed out querying for project item field values", null: false

      def last_five_public_project_v2_item_field_values
        values = MemexProjectColumnValue.joins(memex_project_column: :memex_project)
          .where(creator: @object.account, memex_project: { public: true })
          .order(updated_at: :desc)
          .limit_execution_time(limit_ms: 2000)
          .limit(5)

        values.map do |value|
          col = MemexProjectColumn.find(value.memex_project_column_id)
          item = MemexProjectItem.find(value.memex_project_item_id)
          Platform::Helpers::ProjectV2ItemFieldValue.coerce(value, item, col)
        end
      rescue ActiveRecord::StatementTimeout
        []
      end

      field :private_actions_minute_usage, Integer, null: false do
        description "Total actions minutes used in the past month for private repos owned by the account. If the account is a user then this includes actions run in private repos owned by 25 of the user's most recently created owned orgs. -1 means a timeout occured and the account may have many actions run."
        argument :organizations_query_timeout_ms, Integer,
          description: "Milliseconds to wait for organizations query to complete before returning -1",
          required: false,
          default_value: 1000
        argument :billing_api_timeout_ms, Integer,
          description: "Milliseconds to wait for the Billing API to return before returning -1",
          required: false,
          default_value: 5000
      end

      sig { params(organizations_query_timeout_ms: Integer, billing_api_timeout_ms: Integer).returns(Integer) }
      def private_actions_minute_usage(organizations_query_timeout_ms: 1000, billing_api_timeout_ms: 5000)
        accounts = [@object.account]
        if @object.account.user?
          accounts += @object.account.owned_organizations
            .order(created_at: :desc)
            .limit_execution_time(limit_ms: organizations_query_timeout_ms)
            .limit(25)
        end

        timeout_counter = GitHub::TimeoutCounter.new(billing_api_timeout_ms)
        timeout_value = -1 # Consumers of this API know that -1 means a timeout occurred

        minutes = accounts.sum do |account|
          break if timeout_counter.timeout?

          timeout_counter.update do
            usage = Billing::ActionsUsage.product_usage(account, starts_at: 1.month.ago.in_billing_timezone.beginning_of_day)
            raise Billing::Api::ClientWrapper::BillingClientError, "Unable to fetch actions usage from billing API" if usage.has_error? # rubocop:disable GitHub/UsePlatformErrors
            usage.total_standard_runners_minutes_used
          end
        end
        timeout_counter.timeout? ? timeout_value : minutes.to_i
      rescue ActiveRecord::StatementTimeout, Billing::Api::ClientWrapper::BillingClientError
        timeout_value
      end

      sig { params(account: ::User).returns(T::Array[Integer]) }
      def recent_owned_and_org_owned_repo_ids(account)
        account_ids = [account.id]
        if account.user?
          account_ids += account.owned_organizations.order(created_at: :desc).limit(25).pluck(:id)
        end

        Repositories.domain.recent_by_owner_ids(owner_ids: account_ids, limit: 100)
      end

      field :action_workflows_run_count, Integer, description: "Total number of actions workflows run on the first 100 most recently created repositories owned by the account. If the account is a user then this includes actions run in repos owned by 25 of the user's most recently created owned orgs. -1 means a timeout occured and the account may have many actions run", null: false
      sig { returns(Integer) }
      def action_workflows_run_count
        repo_ids = recent_owned_and_org_owned_repo_ids(@object.account)

        Actions::WorkflowRun.annotate("cross-shard-query-exempted").where(repository_id: repo_ids)
                            .limit_execution_time(limit_ms: 2000)
                            .count(:id)
      rescue ActiveRecord::StatementTimeout
        -1
      end

      field :recent_action_workflows_runs, Connections.define(Objects::ActionsWorkflowRunStafftoolsInfo), description: "Most recent actions workflows run on the first 100 most recently created repositories owned by the account. If the account is a user then this includes actions run in repos owned by 25 of the user's most recently created owned orgs.", null: false, connection: true
      sig { returns(T::Array[Actions::WorkflowRun]) }
      def recent_action_workflows_runs
        repo_ids = recent_owned_and_org_owned_repo_ids(@object.account)

        runs = Actions::WorkflowRun
          .annotate("cross-shard-query-exempted")
          .where(repository_id: repo_ids)
          .order(id: :desc)
          .limit_execution_time(limit_ms: 2000)
          .to_a

        ArrayWrapper.new(runs)
      end

      field :owned_codespaces_created, Integer, description: "Total number of codespaces owned by this account for all time or since a date. -1 means a timeout occured and the account may have many codespaces", null: false do
        argument :since, Scalars::DateTime, "Allows limiting count to codespaces created since a particular date.", required: false
      end
      def owned_codespaces_created(since: nil)
        T.unsafe(User.limit_execution_time(limit_ms: 2000))
          .owned_codespaces_count(@object.account, since)
      rescue ActiveRecord::StatementTimeout
        -1
      end

      field :billed_codespaces_created, Integer, description: "Total number of codespaces billed to account for all time or since a date. -1 means a timeout occured and the account may have many codespaces", null: false do
        argument :since, Scalars::DateTime, "Allows limiting count to codespaces created since a particular date.", required: false
      end
      def billed_codespaces_created(since: nil)
        T.unsafe(User.limit_execution_time(limit_ms: 2000)).billed_codespaces_count(@object.account, since)
      rescue ActiveRecord::StatementTimeout
        -1
      end

      field :codespaces_spending_limit, Float, description: "The current codespaces spending limit for the account.", null: false
      sig { returns(Float) }
      def codespaces_spending_limit
        budget = @object.account.budget_for(group: :codespaces)
        if budget&.enforce_spending_limit?
          budget.usage_limit.to_f
        else
          -1.0
        end
      end

      field :codespaces_spending_limit_unlimited, Boolean, description: "Does the account have an unlimited codespaces budget set?", null: false
      sig { returns(T::Boolean) }
      def codespaces_spending_limit_unlimited
        @object.account.budget_for(group: :codespaces).unlimited_spending_limit?
      end

      field :codespaces_amount_spent, Float, description: "The amount codespaces use the account has accrued for this billing cycle. A value of -1.0 means the billing API had an issue.", null: false
      sig { returns(Promise[Float]) }
      def codespaces_amount_spent
        @object.account.async_customer.then do
          begin
            Billing::Api::ClientWrapper.new(billable_owner: @object.account)
            .codespaces_monthly_usage
            .total_cost_in_subunits
          rescue Billing::Api::ClientWrapper::BillingClientError => e
            Failbot.report(e)

            -1.0
          end
        end
      end

      field :in_dunning_cycle, Boolean, description: "Whether the account is in a dunning cycle (when an account charge is declined from the bank).", null: false
      sig { returns(T::Boolean) }
      def in_dunning_cycle
        @object.account.dunning?
      end

      field :codespaces_tier, Integer, description: "The calculated codespace tier of the account", null: false
      sig { returns(Integer) }
      def codespaces_tier
        Codespaces::Tier.for_billable_owner(@object.account).tier
      end

      field :recent_owned_codespaces, Connections.define(Objects::Codespace), description: "The N recently created codespaces owned by this account. Default is 5 codespaces. An empty array may mean the query timed out.", null: false, connection: true do
        argument :order_by, Inputs::CodespaceOrder,
          "Ordering options for codespaces returned.",
          required: false, default_value: { field: "created_at", direction: "DESC" }
      end
      sig { params(order_by: Inputs::CodespaceOrder, first: Integer).returns(T::Array[::Codespace]) }
      def recent_owned_codespaces(order_by:, first: 5)
        codespaces = Codespace.unscoped
          .where(owner: @object.account)
          .order("workspaces.#{order_by[:field]} #{order_by[:direction]}")
          .limit_execution_time(limit_ms: 2000)
          .to_a

        ArrayWrapper.new(codespaces)
      rescue ActiveRecord::StatementTimeout => e
        Failbot.report(e)

        ArrayWrapper.new([])
      end

      field :recent_billed_codespaces, Connections.define(Objects::Codespace), description: "The N recently codespaces that the User or Organization is the billable owner for. An empty array may mean the query timed out.", null: false, connection: true do
        argument :order_by, Inputs::CodespaceOrder,
          "Ordering options for codespaces returned.",
          required: false, default_value: { field: "created_at", direction: "DESC" }
      end
      sig { params(order_by: Inputs::CodespaceOrder, first: Integer).returns(T::Array[::Codespace]) }
      def recent_billed_codespaces(order_by:, first: 5)
        codespaces = Codespace.unscoped
          .where(billable_owner: @object.account)
          .order("workspaces.#{order_by[:field]} #{order_by[:direction]}")
          .limit_execution_time(limit_ms: 2000)
          .to_a

        ArrayWrapper.new(codespaces)
      rescue ActiveRecord::StatementTimeout => e
        Failbot.report(e)

        ArrayWrapper.new([])
      end

      field :codespaces_compute_usage, Integer, description: "Total number of codespace compute minutes used for the account. Organizations will aggregate across all member use. Users aren't supported yet, returning -2. -1 means an error occurred talking from the Billing API", null: false do
        argument :number_of_days_ago, Integer, "Compute the codespace compute usage between this number of days ago and the present day. Note that going farther back than the beginning of the current billing period has no SLA from GitHub Billing.", default_value: 30, required: false
      end
      sig { params(number_of_days_ago: Integer).returns(Promise[T.nilable(Integer)]) }
      def codespaces_compute_usage(number_of_days_ago: 30)
        @object.account.async_customer.then do
          client = Billing::Api::ClientWrapper.new(billable_owner: @object.account.billable_owner, owner: @object.account)
          product_usage_start = @object.account.start_of_billing_day_with_timezone(number_of_days_ago.days.ago)

          product_usage = T.cast(client.list_product_usage(
            product_usage_start, budget_group: :CODESPACES
          ).extend(Billing::Api::ListProductUsageMethods), Billing::Api::ClientWrapper::ListProductUsageResponseType)

          if product_usage.has_error?
            -1
          else
            product_usage.compute_effective_usage
          end
        end
      end

      field :active_coupon_redemption, Objects::CouponRedemption, description: "The active coupon redemption for the account.", null: true
      sig { returns(Promise[T.nilable(::CouponRedemption)]) }
      def active_coupon_redemption
        Loaders::Prelude.load(@object.account, :coupon_redemption).then do |coupon_redemption|
          coupon_redemption
        end
      end

      field :copilot_is_technical_preview_user, Boolean, description: "Was the account part of the Technical Preview for Copilot?", null: false
      sig { returns(Promise[T::Boolean]) }
      def copilot_is_technical_preview_user
        return Promise.resolve(T.let(false, T::Boolean)) unless @object.account.user?
        Copilot::User.new(@object.account).async_is_technical_preview_user?
      end

      field :copilot_blocked, Boolean, description: "Has this account been blocked from accessing Copilot?", null: false
      sig { returns(T::Boolean) }
      def copilot_blocked
        return false unless @object.account.user?
        Copilot::User.new(@object.account).administrative_blocked?
      end

      field :copilot_access_type, String, description: "Copilot access type", null: false
      sig { returns(String) }
      def copilot_access_type
        return "none" unless @object.account.user?

        copilot_user = Copilot::User.new(@object.account)
        auth = Copilot::Authorizer.new(copilot_user, include_snippy: false)
        auth.access_type_sku
      end

      field :has_copilot_paid_access, Boolean, description: "Has this account paid for Copilot access?", null: false
      sig { returns(T::Boolean) }
      def has_copilot_paid_access
        return false unless @object.account.user?

        copilot_user = Copilot::User.new(@object.account)
        copilot_user.has_paid_access?
      end

      field :has_copilot_cfi_access, Boolean, description: "Does this account have Copilot for Individuals access?", null: false
      sig { returns(T::Boolean) }
      def has_copilot_cfi_access
        return false unless @object.account.user?

        copilot_user = Copilot::User.new(@object.account)
        copilot_user.has_cfi_access?
      end

      field :has_copilot_cfb_access, Boolean, description: "Does this account have Copilot for Business access?", null: false
      sig { returns(T::Boolean) }
      def has_copilot_cfb_access
        return false unless @object.account.user?

        copilot_user = Copilot::User.new(@object.account)
        copilot_user.has_cfb_access?
      end

      field :high_profile, Objects::HighProfile, description: "If the user meets Trust & Safety high profile criteria", null: true
      sig { returns(T.nilable(T::Hash[T::Boolean, String])) }
      def high_profile
        is_high_profile, high_profile_reason = HighProfileSignals.high_profile_user?(@object.account)
        return nil unless is_high_profile

        {
          is_high_profile: is_high_profile,
          reason: high_profile_reason
        }
      end

      private

      # Private: Gets the accounts trade screening record
      #
      # Helper to keep things clean as the trade screening record
      # is referenced a few times in the fields above.
      def async_trade_screening_record
        @object.account.async_trade_screening_record
      end

      # Private: Gets the accounts trade controls restriction
      #
      # Helper to keep things clean as the trade controls restriction
      # is referenced a few times in the fields above.
      def async_trade_controls_restriction
        @object.account.async_trade_controls_restriction
      end
    end
  end
end
