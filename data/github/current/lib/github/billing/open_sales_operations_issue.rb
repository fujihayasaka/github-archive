# typed: strict
# frozen_string_literal: true

module GitHub
  module Billing
    class OpenSalesOperationsIssue
      extend T::Sig

      SALES_OPS_REPO_NWO = "github/sales-operations"
      SALES_OPS_REPO_ID = 20260861
      SALES_SUPPORT_LABEL = "sales-support"
      HIGH_PRIORITY_LABEL = "Priority - High"
      FOOTER = "cc @github/sales-support @github/gitcoin :eyes:"
      include UrlHelpers

      sig do
        params(
          title: String,
          description: String,
          account: T.nilable(::Billing::Types::OrgOrBusiness)
        ).returns(T.nilable(::Issue))
      end
      def self.create(title, description, account = nil)
        new(title, description, account).create
      end

      sig do
        params(
          title: String,
          description: String,
          account: T.nilable(::Billing::Types::OrgOrBusiness)
        ).returns(T.nilable(T.any(::Issue, ::IssueComment)))
      end
      def self.create_or_update(title, description, account = nil)
        new(title, description, account).create_or_update
      end

      # Public: Initialize a new command object
      #
      sig do
        params(
          title: String,
          description: String,
          account: T.nilable(::Billing::Types::OrgOrBusiness)
        ).void
      end
      def initialize(title, description, account = nil)
        @account = account
        @title = title
        @description = description
      end

      # Public: Determines whether we will be able to create an issue by validating title and
      # description args are present and confirms we are able to find the sales-operations repo
      sig { returns(T::Boolean) }
      def valid?
        if [@title, @description].any?(&:blank?)
          Failbot.report(ArgumentError.new "title and description required")
          return false
        end

        return false unless repo
        return false unless sales_ops_repo?

        true
      end

      # Public: Creates a new sales-operations issue or returns nil if we can't
      sig { returns(T.nilable(::Issue)) }
      def create
        return unless valid?
        repo = T.must(self.repo)

        repo.issues.create!(user: User.staff_user,
                            repository_id: repo.id,
                            title: title,
                            body: description,
                            labels: labels)
      end

      # Public: Creates a new sales-operations issue if one doesn't exist, or if one exists,
      # creates a new comment on that issue, or returns nil if this object has bad inputs
      sig { returns(T.nilable(T.any(::Issue, ::IssueComment))) }
      def create_or_update
        return unless valid?

        existing_issue ? update : create
      end

      # Public: The body of the issue
      sig { returns(String) }
      def body
        return description + footer if account.blank?

        description + account_info + footer
      end

      private

      sig { returns(T.nilable(::Billing::Types::OrgOrBusiness)) }
      attr_reader :account
      sig { returns(String) }
      attr_reader :title
      sig { returns(String) }
      attr_reader :description

      # Internal: This method will check if the sales-operations repo exists
      sig { returns(T::Boolean) }
      def sales_ops_repo?
        "#{repo&.owner_display_login}/#{repo&.name}" == SALES_OPS_REPO_NWO
      end

      # Internal: Creates a new comment on the existing issue
      sig { returns(::IssueComment) }
      def update
        T.must(existing_issue).comments.create!(user: User.staff_user, body: description)
      end

      sig { returns(T.nilable(::Issue)) }
      def existing_issue
        @existing_issue ||= T.let(T.must(repo).issues.find_by(title: title, state: "open"), T.nilable(::Issue))
      end

      sig { returns(T::Array[::Label]) }
      def labels
        T.must(repo).labels.where(name: [HIGH_PRIORITY_LABEL, SALES_SUPPORT_LABEL]).to_a
      end

      sig { returns(T.nilable(::Repository)) }
      def repo
        @repo ||= T.let(Repositories::Public.find_active(SALES_OPS_REPO_ID), T.nilable(::Repository))
      end

      # Internal: Identifier and type of account
      sig { returns(String) }
      def name
        case account = self.account
        when Business
          "#{account.display_login} (Enterprise Account)"
        when Organization
          "#{account.display_login} (Organization)"
        else
          ""
        end
      end

      # Internal: The billing partner link for the existing account in markdown format
      sig { returns(String) }
      def account_billing_partner_link
        # Since we don't have an Azure equivalent at this time
        return "" if account&.billed_through_azure_subscription?

        account_zuora_link
      end

      # Internal: The Zuora link to the existing account in markdown format
      sig { returns(String) }
      def account_zuora_link
        "[#{name} in Zuora](#{GitHub.zuora_host}/apps/CustomerAccount.do?method=view&id=#{account&.customer&.zuora_account_id})"
      end

      # Internal: The stafftools link to the existing account in markdown format
      sig { returns(String) }
      def account_stafftools_link
        return "" unless account

        url_options = { host: "admin.github.com", protocol: "https" }

        url = case account
        when Business
          stafftools_enterprise_url(account, **url_options)
        when Organization
          stafftools_user_url(account, **url_options)
        end

        "[#{name} in Stafftools](#{url})"
      end

      # Internal: The account info section that will be inserted between the description and footer
      sig { returns(String) }
      def account_info
        <<~ACCOUNT

          ## Account Info
          **Customer**: #{name}
          #{account_stafftools_link}
          #{account_billing_partner_link}
        ACCOUNT
      end

      # Internal: The footer that will be appended to the issue's description input
      sig { returns(String) }
      def footer
        "\n#{FOOTER}"
      end
    end
  end
end
