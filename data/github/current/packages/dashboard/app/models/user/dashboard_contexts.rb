# typed: true
# frozen_string_literal: true

class User
  class DashboardContexts
    attr_reader :user

    # For performance reasons, we limit how many orgs we display in the contexts
    # dropdown.
    CONTEXT_ORGS_LIMIT = 150

    def initialize(user:)
      @user = user
    end

    # Public: The total count of organizations that can be dashboard contexts.
    #         Note that this is the total count – the actual number displayed
    #         is limited by `CONTEXT_LIMIT`.
    #
    # Returns an Integer.
    def count
      # add 1 to the count to include the current user
      @count ||= context_organization_ids.size + 1
    end

    # Public: The displayable dashboard contexts for this user, limited by
    #         CONTEXT_LIMIT.
    #
    # Returns an Array[User::DashboardContexts::Context].
    def contexts
      return @contexts if defined?(@contexts)

      orgs = scope.order(login: :asc).limit(CONTEXT_ORGS_LIMIT)
      accounts = [user] + orgs

      @contexts = accounts.map do |account|
        Context.new(
          account: account,
          adminable: adminable?(account),
          billing_manager: billing_organization_ids.include?(account.id),
        )
      end
    end

    # Public: Indicates if there are contexts that this user would be able to
    #         switch between.
    #
    # Returns a Boolean.
    def switchable?
      count > 1
    end

    private

    def member_organization_ids
      @member_organization_ids ||= user.organization_ids
    end

    def owned_organization_ids
      @owned_organization_ids ||= user.owned_organization_ids
    end

    def billing_organization_ids
      @billing_organization_ids ||= user.billing_manager_organization_ids
    end

    def context_organization_ids
      @context_organization_ids ||= begin
        Set.new(member_organization_ids) | Set.new(billing_organization_ids)
      end
    end

    # Private: Indicates if an account is adminable by the user.
    #
    # account - The User or Organization to check.
    #
    # Returns a Boolean.
    def adminable?(account)
      return true if account.id == user.id
      owned_organization_ids.include?(account.id)
    end

    def scope
      Organization.where(id: context_organization_ids)
    end

    class Context
      attr_reader :account, :adminable, :billing_manager
      alias_method :adminable?, :adminable
      alias_method :billing_manager?, :billing_manager

      def initialize(account:, adminable:, billing_manager:)
        @account         = account
        @adminable       = adminable
        @billing_manager = billing_manager
      end
    end
  end
end
