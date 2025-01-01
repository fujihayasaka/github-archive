# typed: strict
# frozen_string_literal: true

module Stafftools
  module BillingHelper
    extend T::Helpers

    include ActionView::Helpers::TextHelper
    include StafftoolsHelper

    # TODO: required until we extract the method that uses this
    # into a separate module
    sig { returns(T.nilable(::User)) }
    def current_user
      super
    end

    # Public: Returns the Zuora account url for a given customer
    sig { params(customer: T.nilable(Customer)).returns(T.nilable(String)) }
    def zuora_account_url_for_customer(customer)
      return unless customer
      "#{GitHub.zuora_host}/apps/CustomerAccount.do?method=view&id=%s" % [customer.zuora_account_id]
    end

    sig { params(plan_subscription: T.nilable(::Billing::Types::Subscription)).returns(T.nilable(String)) }
    def zuora_subscription_url_for_plan_subscription(plan_subscription)
      return unless plan_subscription
      subscription_id = plan_subscription.zuora_subscription_id
      "#{GitHub.zuora_host}/apps/Subscription.do?method=view&id=%s" % [subscription_id]
    end

    # Public: Returns the Zuora product url for a given product_id and optional rate_plan_id
    #
    # product_id - string of a Zuora product id
    # rate_plan_id - string of a Zuora rate plan id
    #
    sig { params(product_id: T.nilable(String), rate_plan_id: T.nilable(String)).returns(T.nilable(String)) }
    def zuora_product_url(product_id: nil, rate_plan_id: nil)
      return unless product_id.present?
      product_url = "#{GitHub.zuora_host}/apps/Product.do?method=view&id=#{product_id}"
      if rate_plan_id.present?
        product_url << "##{rate_plan_id}"
      end
      product_url
    end

    sig { params(user: ::User).returns(T::Array[T::Array[String]]) }
    def available_plan_options_for_select(user)
      is_org = user.organization?
      available_plans = if is_org
        GitHub::Plan.all_org_plans
      else
        [GitHub::Plan.free, GitHub::Plan.pro]
      end

      available_plans.map do |plan|
        display_name = plan.display_name(user.type).titleize
        if plan.per_seat?
          if plan.business_plus?
            ["#{display_name} - Unlimited private repositories, SAML SSO, guaranteed uptime, and email support",
              plan.name]
          else
            ["#{display_name} - Unlimited private repositories", plan.name]
          end
        else
          if plan.free_with_addons?
            ["#{display_name} with addons", plan.name]
          else
            repo_count = is_org ? plan.org_repos : plan.repos
            ["#{display_name} - #{repo_count} private repositories", plan.name]
          end
        end
      end
    end

    sig do
      params(billing_transaction: T.any(::Billing::BillingTransaction, ::Stafftools::Billing::PaymentRecord))
        .returns(String)
    end
    def refund_path_for(billing_transaction)
      url_helpers = Rails.application.routes.url_helpers
      if billing_transaction.live_user.present?
        url_helpers.stafftools_user_refund_transaction_path(user: billing_transaction.user_login,
          transaction_id: billing_transaction.transaction_id)
      else
        url_helpers.stafftools_billing_transactions_refund_path(transaction_id: billing_transaction.transaction_id)
      end
    end

    sig { returns(T::Array[T::Array[String]]) }
    def plan_duration_options_for_select
      [
        %w[Monthly month],
        %w[Yearly year],
      ]
    end

    sig { params(user: ::User).returns(T::Array[T::Array[String]]) }
    def gift_type_options_for_select(user)
      if user.teacher_gift?
        [
          ["Normal account", "card"],
          ["Teacher or student group", "teacher"],
        ]
      else
        [
          ["Normal account", "card"],
          ["Gift account", "gift"],
        ]
      end
    end

    sig { params(user: ::User).returns(String) }
    def formatted_account_outside_collaborators_count(user)
      "%s with private access" % [
        pluralize(
          user.collaborators_on_private_repositories_without_invitations.size,
          GitHub.outside_collaborators_flavor.singularize,
        ),
      ]
    end

    sig { params(user: ::User).returns(String) }
    def formatted_account_private_repository_invitations_counts(user)
      total_invite_count = user.private_repo_invitee_ids.size
      if total_invite_count > 0
        unique_invite_count = user.private_repo_non_collaborator_invitee_ids.size
        "%s unique / %s total private repository invitations" % [unique_invite_count, total_invite_count]
      else
        "0 private repository invitations"
      end
    end

    sig { params(target: ::Billing::Types::Account, include_sponsors: T::Boolean).returns(String) }
    def stafftools_billing_audit_log_path(target, include_sponsors: false)
      queries = [
        "action startswith 'account.'",
        "action startswith 'billing.'",
        "action startswith 'billing_customer.'",
        "action startswith 'blocklisted_payment_method.'",
        "action startswith 'braintree.'",
        "action startswith 'invoice_email_preference.'",
        "action startswith 'metered_billing_configuration.'",
        "action startswith 'payment_method.'",
        "action startswith 'pending_plan_change.'",
        "action startswith 'pending_subscription_change.'",
        "action startswith 'plan_subscription.'",
        "action == 'staff.chargeback_disable'",
        "(action == 'config_entry.create' and data.name startswith 'SELF_SERVE_INVOICE')",
      ]
      queries << "action startswith 'sponsors.'" if include_sponsors

      if target.business?
        queries << "(action startswith 'business.' and action != 'business.sso_response')"
      elsif target.organization?
        queries << "action == 'business.add_organization'"
        queries << "action == 'business.remove_organization'"
        queries << "action == 'copilot.cfb_seat_management_changed'"
        queries << "action == 'org.transform'"
      end

      base_query = stafftools_audit_log_query(target).dup

      billing_query = if GitHub.driftwood_ade_queries_enabled?
        "#{base_query} and (#{queries.join(" or ")})"
      else
        # Convert queries to the legacy format
        queries.map! do |query|
          query
            .gsub(/ == '([^']*)'/, ':\1')           # convert '==' queries
            .gsub(/ startswith '([^']*)'/, ':\1*')  # convert 'startswith' queries
            .gsub(/ and /, " AND ")                 # 'and' -> 'AND'
            .gsub(/ or /, " OR ")                   # 'or' -> 'OR'
        end

        "#{base_query} AND (#{queries.join(" OR ")})"
      end

      Rails.application.routes.url_helpers.stafftools_audit_log_path(query: billing_query)
    end

    sig { params(target: ::Billing::Types::Account).returns(String) }
    def organization_upgrade_audit_log_path(target)
      query = "action == 'business.upgrade_from_organization'"

      base_query = stafftools_audit_log_query(target).dup

      upgrade_query = if GitHub.driftwood_ade_queries_enabled?
        "#{base_query} and #{query}"
      else
        query
          .gsub(/ == '([^']*)'/, ':\1')           # convert '==' queries
          .gsub(/ startswith '([^']*)'/, ':\1*')  # convert 'startswith' queries
          .gsub(/ and /, " AND ")                 # 'and' -> 'AND'
          .gsub(/ or /, " OR ")                   # 'or' -> 'OR'

        "#{base_query} AND #{query}"
      end

      Rails.application.routes.url_helpers.stafftools_audit_log_path(query: upgrade_query)
    end

    # Skip billing checks for :packages and :storage
    # Adds a comment in the github/gitcoin tracking issue 4042 for tracking
    sig { params(billing_entity: T.nilable(::Billing::Types::Account), current_user: T.nilable(::User)).returns(String) }
    def stop_billing_check_packages(billing_entity, current_user)
      if billing_entity
        if billing_entity.skip_metered_billing_permission_check_for?(product: :packages) && billing_entity.skip_metered_billing_permission_check_for?(product: :storage)
          "Billing check has already been stopped for #{billing_entity.name}"
        else
          billing_entity.skip_metered_billing_permission_check_for(product: :packages, expires: 1.year.from_now)
          billing_entity.skip_metered_billing_permission_check_for(product: :storage, expires: 1.year.from_now)

          repository = ::Repository.nwo("github/gitcoin")
          if repository
            issue = repository.issues.find_by_number(4042) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
            if issue
              issue.create_comment(current_user, "Packages & Storage billing permission checks have been skipped for : `#{billing_entity.name}`")
              "Billing check has been skipped for : #{billing_entity.name}. Stopped for packages & storage for 1 year from now. Added user for tracking here github/gitcoin/issues/4042"
            else
              "Couldn't add the user '#{billing_entity.name}', for tracking in github/gitcoin/issues/4042, Please add a comment for tracking. Reason:Issue not found"
            end
          else
            "Couldn't add the user '#{billing_entity.name}', for tracking in github/gitcoin/issues/4042, Please add a comment for tracking. Reason: Repository not found"
          end
        end
      else
        "Couldn't skip billing permission check, Please follow the manual process. Reason: User not found"
      end
    end

    sig { params(billing_entity: T.nilable(::Billing::Types::Account), current_user: T.nilable(::User)).returns(String) }
    def stop_billing_check_actions(billing_entity, current_user)
      if billing_entity
        if billing_entity.skip_metered_billing_permission_check_for?(product: :actions) && billing_entity.skip_metered_billing_permission_check_for?(product: :storage)
          "Billing check has already been stopped for #{billing_entity.name}"
        else
          billing_entity.skip_metered_billing_permission_check_for(product: :actions, expires: 4.days.from_now)
          billing_entity.skip_metered_billing_permission_check_for(product: :storage, expires: 4.days.from_now)

          repository = ::Repository.nwo("github/gitcoin")
          if repository
            issue = repository.issues.find_by_number(4042)
            if issue
              issue.create_comment(current_user, "Actions & Storage billing permission checks have been skipped for : `#{billing_entity.name}`")
              "Billing check has been skipped for : #{billing_entity.name}. Stopped for actions & storage for 4 days from now. Added user for tracking here github/gitcoin/issues/4042"
            else
              "Couldn't add the user '#{billing_entity.name}', for tracking in github/gitcoin/issues/4042, Please add a comment for tracking. Reason:Issue not found"
            end
          else
            "Couldn't add the user '#{billing_entity.name}', for tracking in github/gitcoin/issues/4042, Please add a comment for tracking. Reason: Repository not found"
          end
        end
      else
        "Couldn't skip billing permission check, Please follow the manual process. Reason: User not found"
      end
    end

    # Format metered product array/hash value to be more human readable
    sig { params(value: T.any(T::Array[String], T::Hash[T.untyped, T.untyped], String)).returns(String) }
    def format_metered_product_value(value)
      case value
      when Array
        safe_join(value.map { |v| format_metered_product_value(v) }, tag(:br))
      when Hash
        safe_join(value.map { |k, v| "#{k}: #{v}" }, tag(:br)) + tag(:br)
      else
        value
      end
    end

    sig { params(entity: T.any(::User, ::Organization)).returns(String) }
    def stafftools_billing_vnext_usage_path(entity:)
      if entity.delegate_billing_to_business?
        Rails.application.routes.url_helpers.stafftools_enterprise_billing_usage_path(entity.business, query: "org:#{entity.display_login}")
      else
        Rails.application.routes.url_helpers.stafftools_user_billing_usage_path(entity.display_login)
      end
    end

    sig { returns(String) }
    def reused_card_fingerprints_kusto_dashboard_url
      "https://dataexplorer.azure.com/dashboards/7ad3cee5-94c1-4207-b5ec-afa8b0dee770"
    end
  end
end
