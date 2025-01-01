# typed: strict
# frozen_string_literal: true

require "digest"

module Billing
  module Azure
    class InvalidSubscriptionNotifier
      extend T::Sig

      SALES_OPS_REPO_NWO = "github/sales-operations"
      INSTRUCTIONS_LINK = "https://github.com/github/gitcoin/discussions/5462"
      ENTERPRISE_ACCOUNT_SETUP_LABEL = "Enterprise Account Set-up"
      SALES_SUPPORT_LABEL = "sales-support"

      sig { params(business: T.nilable(Business), org: T.nilable(Organization)).returns(T.untyped) }
      def notify(business: nil, org: nil)
        account = business || org
        create_issue(account: T.must(account))
      end

      private

      sig { params(account: Billing::Types::OrgOrBusiness).returns(T.untyped) }
      def create_issue(account:)
        ActiveRecord::Base.connected_to(role: :writing) do
          repository = Repository.nwo(SALES_OPS_REPO_NWO)

          if repository.nil?
            # Increment counter and Skip if the configured repository doesn't exist
            GitHub.dogstats.increment("billing.enterprise_agreement.sales_operations.repo_not_found")
            return
          end

          existing_issue = get_existing_open_issue(repository: repository, account: account)

          if existing_issue.nil?
            # If an existing Open issue is not found, create one.
            repository.issues.create!(
              user: User.staff_user,
              repository_id: repository.id,
              title: issue_title(account: account),
              body: issue_body(account: account),
              labels: repository.labels.where(name: [ENTERPRISE_ACCOUNT_SETUP_LABEL, SALES_SUPPORT_LABEL])
            )
          else
            # An issue already exists and is Open, add comment to the issue.
            return if pause_subsequent_comments_for?(account: account)
            existing_issue.comments.create!(
              user: User.staff_user,
              body: issue_comment(account: account)
            )
          end
        end
      end

      sig { params(repository: Repository, account: Billing::Types::Account).returns(T.nilable(Issue)) }
      def get_existing_open_issue(repository: , account:)
        repository.issues.where(title: issue_title(account: account), state: "open").last
      end

      sig { params(account: Billing::Types::Account).returns(String) }
      def issue_comment(account:)
        "Subscription ID for customer #{account.name} is still invalid at **#{Time.current.in_time_zone('Eastern Time (US & Canada)')} EST**, please rectify."
      end

      sig { params(account: Billing::Types::Account).returns(String) }
      def issue_body(account:)
        <<~BODY
        ### #{issue_title(account: account)}
        **Item** | **Description**
        :--: | :--:
        **Description** | _latest check for Azure Subsription ID status failed at **#{Time.current.in_time_zone('Eastern Time (US & Canada)')} EST**_
        **Ask** | _Please have their sales rep reach out to get this rectified._
        **Account type** | #{account.business? ? "Enterprise" : "Organization"}
        **Links** | #{account.is_a?(Business) ? "Terms of Service Notes: #{account.terms_of_service_notes}," : nil} [Stafftools](#{staftools_url(account: account)})

        Next Steps
        ---
        1. Reach out to the account contact at **#{account.name}** to get a valid Azure Subscription ID that we can continue to bill them.
        2. Once we have an updated Subscription ID, visit [this link in stafftools](#{staftools_url(account: account)}/billing) to update their Azure Subscription ID.

        **Do not edit the title of this issue, used by automation.**
        BODY
      end

      sig { params(account: Billing::Types::Account).returns(String) }
      def issue_title(account:)
        subscription_digest = Digest::SHA256.hexdigest(T.must(account.customer).azure_subscription_id.to_s)
        "Azure Subscription ID is invalid for #{account.name}, #{subscription_digest[0..12]}"
      end

      sig { params(account: Billing::Types::Account).returns(String) }
      def staftools_url(account:)
        resource = account.business? ? "enterprises" : "users"
        slug = account.is_a?(Business) ? account.slug : account.to_param
        GitHub.stafftools_url + "/stafftools/#{resource}/#{slug}"
      end

      sig { params(account: Billing::Types::Account).returns(T::Boolean) }
      def pause_subsequent_comments_for?(account:)
        # Temporary stop sending subsequent invalid subscription comments for this account.
        account.feature_enabled?(:pause_invalid_subscription_notifier)
      end
    end
  end
end
