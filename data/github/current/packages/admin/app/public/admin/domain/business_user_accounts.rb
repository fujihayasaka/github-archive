# typed: strict
# frozen_string_literal: true

module Admin
  class Domain
    class BusinessUserAccounts < GH::Domain::Base
      # Finds a BusinessUserAccount by its ID.
      #
      # @param id [Integer] The BusinessUserAccount ID.
      # @return [Admin::IBusinessUserAccount, nil] The account if found, otherwise nil.
      sig { params(id: Integer).returns(T.nilable(Admin::IBusinessUserAccount)) }
      def by_id(id)
        return nil if id <= 0

        BusinessUserAccount.find_by(id: id)
      end

      # Finds BusinessUserAccounts by a list of IDs.
      #
      # @param ids [Array<Integer>] The BusinessUserAccount IDs.
      # @return [Array<Admin::IBusinessUserAccount>] The matching accounts.
      sig { params(ids: T::Array[Integer]).returns(T::Array[Admin::IBusinessUserAccount]) }
      def by_ids(ids)
        return [] if ids.empty?

        BusinessUserAccount.where(id: ids).to_a
      end

      # Finds a BusinessUserAccount by business ID and user ID.
      #
      # @param business_id [Integer] The business ID.
      # @param user_id [Integer] The user ID.
      # @return [Admin::IBusinessUserAccount, nil] The account if found, otherwise nil.
      sig { params(business_id: Integer, user_id: Integer).returns(T.nilable(Admin::IBusinessUserAccount)) }
      def by_business_and_user(business_id, user_id)
        return nil if business_id <= 0 || user_id <= 0

        BusinessUserAccount.find_by(business_id: business_id, user_id: user_id)
      end

      # Returns true if a BusinessUserAccount exists for the given business and user.
      # Uses a lightweight EXISTS query — no object is loaded.
      #
      # @param business_id [Integer] The business ID.
      # @param user_id [Integer] The user ID.
      # @return [Boolean] Whether the account exists.
      sig { params(business_id: Integer, user_id: Integer).returns(T::Boolean) }
      def user_belongs_to_business?(business_id, user_id)
        return false if business_id <= 0 || user_id <= 0

        BusinessUserAccount.where(business_id: business_id, user_id: user_id).exists?
      end

      # Finds BusinessUserAccounts by business ID and a list of user IDs.
      #
      # @param business_id [Integer] The business ID.
      # @param user_ids [Array<Integer>] The user IDs to look up.
      # @return [Array<Admin::IBusinessUserAccount>] The matching accounts.
      sig { params(business_id: Integer, user_ids: T::Array[Integer]).returns(T::Array[Admin::IBusinessUserAccount]) }
      def by_business_and_users(business_id, user_ids)
        return [] if business_id <= 0 || user_ids.empty?

        BusinessUserAccount.where(business_id: business_id, user_id: user_ids).to_a
      end

      # Returns the IDs of BusinessUserAccounts matching the given business and user IDs.
      # Uses pluck(:id) to avoid loading full records into memory.
      #
      # @param business_id [Integer] The business ID.
      # @param user_ids [Array<Integer>] The user IDs to look up.
      # @return [Array<Integer>] The matching BusinessUserAccount IDs.
      sig { params(business_id: Integer, user_ids: T::Array[Integer]).returns(T::Array[Integer]) }
      def ids_by_business_and_users(business_id, user_ids)
        return [] if business_id <= 0 || user_ids.empty?

        BusinessUserAccount.where(business_id: business_id, user_id: user_ids).pluck(:id)
      end

      # Returns all BusinessUserAccounts for a given user.
      #
      # @param user_id [Integer] The user ID.
      # @return [Array<Admin::IBusinessUserAccount>] The accounts.
      sig { params(user_id: Integer).returns(T::Array[Admin::IBusinessUserAccount]) }
      def for_user(user_id)
        return [] if user_id <= 0

        BusinessUserAccount.where(user_id: user_id).to_a
      end

      # Returns all BusinessUserAccounts for a given business.
      #
      # @param business_id [Integer] The business ID.
      # @return [Array<Admin::IBusinessUserAccount>] The accounts.
      sig { params(business_id: Integer).returns(T::Array[Admin::IBusinessUserAccount]) }
      def for_business(business_id)
        return [] if business_id <= 0

        BusinessUserAccount.where(business_id: business_id).to_a
      end

      # Returns the user IDs for all members of a business.
      #
      # @param business_id [Integer] The business ID.
      # @return [Array<Integer>] The user IDs.
      sig { params(business_id: Integer).returns(T::Array[Integer]) }
      def user_ids_for_business(business_id)
        return [] if business_id <= 0

        BusinessUserAccount.where(business_id: business_id).pluck(:user_id).compact
      end

      # Returns BusinessUserAccounts with a given role within a business.
      #
      # @param business_id [Integer] The business ID.
      # @param role [Symbol] The role to filter by (e.g. :member, :owner).
      # @return [Array<Admin::IBusinessUserAccount>] The matching accounts.
      sig { params(business_id: Integer, role: Symbol).returns(T::Array[Admin::IBusinessUserAccount]) }
      def with_role(business_id, role)
        return [] if business_id <= 0

        BusinessUserAccount.where(business_id: business_id).merge(BusinessUserAccount.with_business_role(role)).to_a
      end

      # Returns BusinessUserAccounts that hold a GHEC license within a business.
      #
      # @param business_id [Integer] The business ID.
      # @return [Array<Admin::IBusinessUserAccount>] The licensed accounts.
      sig { params(business_id: Integer).returns(T::Array[Admin::IBusinessUserAccount]) }
      def licensed_for_business(business_id)
        return [] if business_id <= 0

        BusinessUserAccount.where(business_id: business_id).merge(BusinessUserAccount.licensed_users).to_a
      end

      # Recomputes and persists the two-factor status for every BusinessUserAccount
      # belonging to the given user.
      #
      # @param user_id [Integer] The user whose BUA two-factor statuses should be synced.
      # @return [void]
      sig { params(user_id: Integer).void }
      def sync_two_factor_status_for_user(user_id)
        return if user_id <= 0

        user = Users.domain.by_id(user_id)
        return if user.nil?

        buas = BusinessUserAccount.where(user_id: user_id)
        first_bua = buas.first
        return if first_bua.nil?

        status = first_bua.two_factor_status_type(user)
        buas.update_all(
          two_factor_status: BusinessUserAccount.two_factor_statuses[T.must(status&.to_s)],
        )
      end

      # Returns user IDs for members of a business who have been inactive since the given threshold.
      # Accounts where last_business_activity_at is NULL are treated as always inactive.
      # When +exclusive_role+ is given, only accounts whose roles are *exclusively* the listed
      # roles are included.
      #
      # @param business_id [Integer] The business ID.
      # @param inactive_since [Time] A point in time; users last active
      #   at or before this value are considered dormant. Callers must precompute this value
      #   (e.g. +30.days.ago+) before passing it in.
      # @param exclusive_role [Symbol, nil] When present, restrict to accounts exclusively holding this role.
      # @return [Array<Integer>] The user IDs.
      sig { params(business_id: Integer, inactive_since: Time, exclusive_role: T.nilable(Symbol)).returns(T::Array[Integer]) }
      def dormant_user_ids_for_business(business_id, inactive_since:, exclusive_role: nil)
        return [] if business_id <= 0

        scope = BusinessUserAccount
          .where(business_id: business_id)
          .where("last_business_activity_at IS NULL OR last_business_activity_at <= ?", inactive_since)

        scope = scope.exclusive_roles(exclusive_role) if exclusive_role.present?

        scope.pluck(:user_id).compact
      end

      ## TODO: This likely can be removed in favor of refactoring the caller.
      # Clears the ghec_license field for all BusinessUserAccounts belonging to the given business.
      # Used when transitioning a business away from metered licensing.
      #
      # @param business_id [Integer] The business ID.
      sig { params(business_id: Integer).void }
      def clear_ghec_license_for_business(business_id)
        return if business_id <= 0

        BusinessUserAccount.where(business_id: business_id).update_all(ghec_license: nil)
      end

      # Adds a business role to accounts for the given user IDs within a business.
      # Only accounts that already exist for the (business_id, user_id) pairs are affected.
      #
      # @param role [Symbol] The role to add (e.g. :member, :owner).
      # @param business_id [Integer] The business ID.
      # @param user_ids [Array<Integer>] The user IDs whose accounts should receive the role.
      # @return [void]
      sig { params(role: Symbol, business_id: Integer, user_ids: T::Array[Integer]).void }
      def add_role_to_accounts(role, business_id, user_ids)
        return if business_id <= 0 || user_ids.empty?

        accounts = BusinessUserAccount.where(business_id: business_id, user_id: user_ids)
        BusinessUserAccount.add_business_role_to_accounts(role, accounts)
      end

      # Enqueues a BusinessUserAccountUpdateAttributesJob for the given business,
      # scoped to the BusinessUserAccount IDs that correspond to the provided user IDs.
      #
      # @param business_id [Integer] The business ID.
      # @param user_ids [Array<Integer>] The user IDs to update.
      # @return [void]
      sig { params(business_id: Integer, user_ids: T::Array[Integer]).void }
      def enqueue_update_attributes(business_id, user_ids)
        return if business_id <= 0

        bua_ids = BusinessUserAccount.where(business_id: business_id, user_id: user_ids).pluck(:id)
        BusinessUserAccountUpdateAttributesJob.perform_later(business_id: business_id, user_account_ids: bua_ids)
      end

      # Enqueues BusinessUserAccountUpdateUserJob for the given accounts, grouped by business.
      #
      # Pass either +bua_ids+ (BusinessUserAccount IDs) or +user_ids+ (User IDs); when
      # +user_ids+ is provided the matching BUA IDs are resolved internally.
      #
      # @param bua_ids [Array<Integer>] The BusinessUserAccount IDs to refresh.
      # @param user_ids [Array<Integer>] The user IDs whose BUAs should be refreshed.
      # @return [void]
      sig { params(bua_ids: T::Array[Integer], user_ids: T::Array[Integer]).void }
      def enqueue_update_user(bua_ids: [], user_ids: [])
        if bua_ids.empty? && user_ids.present?
          bua_ids = BusinessUserAccount.where(user_id: user_ids).where.not(business_id: nil).pluck(:id)
        end

        return if bua_ids.empty?

        groups = BusinessUserAccount
          .where(id: bua_ids)
          .where.not(business_id: nil)
          .pluck(:business_id, :id)
          .group_by(&:first)

        return if groups.empty?

        Business.where(id: groups.keys).each do |business|
          ids = groups[business.id].map(&:last)
          BusinessUserAccountUpdateUserJob.perform_later(business, user_account_ids: ids)
        end
      end

      # Converts an array of role symbols to a bitmask integer.
      # Delegates to +BusinessUserAccount.roles_bitmask+.
      #
      # @param roles [Array<Symbol>] The role symbols from +BusinessUserAccount::Roles::BUSINESS_ROLES+.
      # @return [Integer] The resulting bitmask.
      sig { params(roles: T::Array[Symbol]).returns(Integer) }
      def roles_bitmask(roles)
        BusinessUserAccount.roles_bitmask(roles)
      end

      # Returns the user IDs of BusinessUserAccounts belonging to a business
      # whose login matches any of the given logins.
      # When +submatch+ is true, each login is treated as a LIKE pattern.
      #
      # @param business_id [Integer] The business ID.
      # @param logins [Array<String>] The login values to match.
      # @param submatch [Boolean] When true, matches using LIKE "%login%".
      # @param limit [Integer, nil] Maximum number of results to return.
      # @return [Array<Integer>] The matching user IDs.
      sig { params(business_id: Integer, logins: T::Array[String], submatch: T::Boolean, limit: T.nilable(Integer)).returns(T::Array[Integer]) }
      def user_ids_by_business_and_logins(business_id, logins, submatch: false, limit: nil)
        return [] if business_id <= 0 || logins.empty?

        scope = BusinessUserAccount.where(business_id: business_id)
        scope = if submatch
          table = BusinessUserAccount.arel_table
          scope.where(logins.map { |l| table[:login].matches("%#{l}%") }.reduce(:or))
        else
          scope.where(login: logins)
        end
        scope = scope.limit(limit) if limit
        scope.pluck(:user_id)
      end

      # Returns logins of BusinessUserAccounts for a business, optionally filtered by a
      # login pattern and capped at +limit+ results. Results are sorted alphabetically.
      #
      # Intended for suggestion/autocomplete callers that need login strings, not loaded objects.
      #
      # @param business_id [Integer] The business ID.
      # @param value [String] The current search input. Pass an empty string for no filter.
      # @param limit [Integer] Maximum number of results to return.
      # @return [Array<String>] The matching login strings, sorted.
      sig { params(business_id: Integer, value: String, limit: Integer).returns(T::Array[String]) }
      def logins_for_business(business_id, value:, limit: 10)
        return [] if business_id <= 0

        scope = BusinessUserAccount.where(business_id: business_id)
        scope = scope.where("login LIKE ?", "%#{value}%") if value.present?
        scope.order(:login).limit(limit).pluck(:login).compact
      end

      # Finds a BusinessUserAccount by ID, raising ActiveRecord::RecordNotFound if absent.
      # Use this when the caller expects the record to exist and wants the standard 404 behaviour.
      #
      # @param id [Integer] The BusinessUserAccount ID.
      # @return [Admin::IBusinessUserAccount] The account.
      # @raise [ActiveRecord::RecordNotFound] When no record exists with the given ID.
      sig { params(id: Integer).returns(Admin::IBusinessUserAccount) }
      def find(id)
        BusinessUserAccount.find(id)
      end

      # Returns the org-member-type symbol for a given role string.
      # Delegates to +BusinessUserAccount.org_member_type_from_role+.
      #
      # @param role [String, nil] The role string (e.g. "member", "owner"). Pass nil for "all".
      # @return [Symbol] :admin, :member_without_admin, or :all.
      sig { params(role: T.nilable(String)).returns(Symbol) }
      def org_member_type_from_role(role)
        BusinessUserAccount.org_member_type_from_role(role)
      end

      # Returns all BusinessUserAccounts for any of the given user IDs, across all businesses.
      #
      # @param user_ids [Array<Integer>] The user IDs to look up.
      # @return [Array<Admin::IBusinessUserAccount>] The matching accounts.
      sig { params(user_ids: T::Array[Integer]).returns(T::Array[Admin::IBusinessUserAccount]) }
      def for_users(user_ids)
        return [] if user_ids.empty?

        BusinessUserAccount.where(user_id: user_ids).to_a
      end

      # Returns the business IDs of BusinessUserAccounts where the given user
      # *exclusively* holds the unaffiliated role (i.e. has no other roles).
      #
      # @param user_id [Integer] The user ID.
      # @return [Array<Integer>] The matching business IDs.
      sig { params(user_id: Integer).returns(T::Array[Integer]) }
      def exclusive_unaffiliated_business_ids_for_user(user_id)
        return [] if user_id <= 0

        BusinessUserAccount.where(user_id: user_id).exclusive_unaffiliated_role.pluck(:business_id)
      end

      # Returns the number of businesses where the given user exclusively holds
      # the unaffiliated role.
      #
      # @param user_id [Integer] The user ID.
      # @return [Integer] The count.
      sig { params(user_id: Integer).returns(Integer) }
      def exclusive_unaffiliated_count_for_user(user_id)
        return 0 if user_id <= 0

        BusinessUserAccount.where(user_id: user_id).exclusive_unaffiliated_role.count
      end

      # Destroys all BusinessUserAccounts matching the given user ID and business ID.
      # Delegates to +BusinessUserAccount.destroy_by+.
      #
      # @param user_id [Integer] The user ID.
      # @param business_id [Integer] The business ID.
      # @return [void]
      sig { params(user_id: Integer, business_id: Integer).void }
      def destroy_for_user_and_business(user_id:, business_id:)
        BusinessUserAccount.destroy_by(user_id: user_id, business_id: business_id)
      end

      # Removes BusinessUserAccounts that are unaffiliated (belong to no organization
      # within the business). Delegates to +BusinessUserAccount::SynchronizeAccounts+.
      #
      # @param business [Business] The business to clean up.
      # @param actor [User] The user performing the action.
      # @return [RemoveUnaffiliatedMembersBusinessOrchestration] The orchestration result.
      sig { params(business: Business, actor: User).returns(RemoveUnaffiliatedMembersBusinessOrchestration) }
      def remove_unaffiliated_accounts(business:, actor:)
        BusinessUserAccount::SynchronizeAccounts.new(business: business, actor: actor).remove_unaffiliated_accounts
      end

      # Removes BusinessUserAccount records whose associated user no longer exists.
      # Delegates to +BusinessUserAccount::SynchronizeAccounts+.
      #
      # @param business [Business] The business to clean up.
      # @return [void]
      sig { params(business: Business).void }
      def remove_orphaned_accounts(business:)
        BusinessUserAccount::SynchronizeAccounts.new(business: business).remove_orphaned_accounts
      end
    end
  end
end
