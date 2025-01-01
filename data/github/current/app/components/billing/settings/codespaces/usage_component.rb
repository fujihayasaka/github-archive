# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    module Codespaces
      class UsageComponent < ApplicationComponent
        include GitHub::Memoizer
        include CodespacesHelper

        DOCS_PATH = "/billing/managing-billing-for-github-codespaces/about-billing-for-github-codespaces"

        attr_reader :account, :is_stafftools

        def initialize(
          account:,
          is_stafftools: false,
          usage_source: ""
        )
          @account = account
          @is_stafftools = is_stafftools
          @usage_source = usage_source
        end

        def render?
          codespaces_billing_enabled?(@account)
        end

        def box_title_subtitle
          doc_link = GitHub.developer_help_url + DOCS_PATH

          description = if ::Codespaces::Policy.entitlements_feature_enabled?(@account)
            if days_to_next_metered_billing_date.present?
              "Included quotas reset in #{days_to_next_metered_billing_date}."
            else
              "Included quotas reset next cycle."
            end
          else
            "Pay-as-you-go, billed monthly."
          end

          content_tag(:span, description) + content_tag(:a, " See billing documentation", href: doc_link, class: "Link--inTextBlock")
        end

        # Attempts to resolve the path to the controller we should query account usage for based
        # on account type.
        def usage_source_path
          if @usage_source.present?
            @usage_source
          elsif account.business?
            if is_stafftools
              stafftools_enterprise_billing_codespaces_usage_path(account)
            else
              settings_billing_codespaces_overview_enterprise_path(account)
            end
          elsif account.organization?
            if is_stafftools
              stafftools_user_billing_codespaces_usage_path(account)
            else
              billing_settings_org_codespaces_usage_path(account)
            end
          else
            if is_stafftools
              stafftools_user_billing_codespaces_usage_path(account)
            else
              settings_user_billing_codespaces_usage_path(account)
            end
          end
        end

        private

        memoize def days_to_next_metered_billing_date
          days_to_time(account.next_metered_billing_cycle_starts_at)
        end

        def days_to_time(time)
          days = ((time - GitHub::Billing.timezone.now) / 1.day).to_i
          pluralize_days_for_display(days)
        end

        def pluralize_days_for_display(days)
          "#{days} #{"day".pluralize(days)}"
        end
      end
    end
  end
end
