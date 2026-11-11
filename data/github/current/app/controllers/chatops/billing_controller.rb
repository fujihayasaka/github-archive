# typed: true
# frozen_string_literal: true

require "chatops-controller"

module Chatops
  class BillingController < ApplicationController
    include ::Chatops::Controller

    # CAP and verify_authenticity_token not required on chatops controllers
    # since these chatops are run by Hubbers from Slack and the routes for triggering them are only accessible through our internal network
    skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction
    skip_forgery_protection

    chatops_namespace :billing
    chatops_help "Commands for working with billing engineering related tasks"

    depends_on_clusters ApplicationRecord::Mysql1,
      only: [:list]

    # Mirrors BillingPlatform::Base::CopilotPlan enum values. Used for both
    # entity-driven plan resolution and the `copilot_plan:NAME` CLI override.
    COPILOT_PLAN_NAME_TO_ENUM = {
      "unknown" => 0,
      "business" => 1,
      "enterprise" => 2,
      "individual" => 3,
      "individual_free" => 4,
      "individual_trial" => 5,
      "invalid" => 6,
      "individual_pro_plus" => 7,
      "individual_edu" => 8,
      "individual_max" => 9,
    }.freeze

    # Human-readable trust tier names for the `trust_tier:NAME` CLI override.
    # Integer values are also accepted for backwards compatibility.
    TRUST_TIER_NAME_TO_INT = {
      "trusted" => ::TrustTiers::Tier::TRUSTED,
      "neutral" => ::TrustTiers::Tier::NEUTRAL,
      "untrusted" => ::TrustTiers::Tier::UNTRUSTED,
    }.freeze

    SLACK_COLOR_GREEN = "#1f883d"
    SLACK_COLOR_YELLOW = "#9a6700"
    SLACK_COLOR_RED = "#cf222e"

    chatop :cpwu,
      /cpwu\s+(?<identifier>(enterprise|org|user|customer_id):[^\s]+)\s+(?<product>[^\s]+)\s+(?<sku>[^\s]+)(\s+(?<options>.+))?/,
      "cpwu [enterprise:slug|org:login|user:login|customer_id:id] <product> <sku> [repo_id:ID] [org_id:ID] [actor_id:ID] [quantity:NUMBER] [trust_tier:trusted|neutral|untrusted] [copilot_plan:NAME] - Can Proceed With Usage" do
      account_type, id = jsonrpc_params[:identifier].split(":")
      unless id.present?
        return chatop_send "Please provide a valid #{account_type} identifier enterprise:slug, org:login, user:login, or customer_id:id"
      end

      entity = nil
      customer_id = nil
      customer =
        case account_type
        when "enterprise"
          entity = Business.find_by(slug: id)
          entity&.customer
        when "org", "user"
          entity = User.find_by(login: id)
          entity&.customer
        when "customer_id"
          customer_id = id
          Customer.find_by(id: id)
        end
      customer_id = customer.id if customer_id.nil? && customer.present?

      if customer_id.blank?
        return chatop_send "Unable to imply customer ID from #{account_type} identifier: #{id}"
      end

      product = jsonrpc_params[:product]
      sku = jsonrpc_params[:sku]

      # Parse optional parameters if provided
      options = jsonrpc_params[:options] || ""
      options_hash = {}
      options.scan(/(\w+):(\S+)/).each do |key, value|
        options_hash[key] = value
      end

      repo_id = options_hash["repo_id"]
      org_id = options_hash["org_id"]
      actor_id = options_hash["actor_id"]
      quantity = options_hash["quantity"]
      trust_tier_override = options_hash["trust_tier"]
      copilot_plan_override = options_hash["copilot_plan"]

      # Actor-scoped feature flags keyed on the invoking Hubber.
      chatop_user = ::User.find_by(login: params[:user])
      send_copilot_plan = chatop_user.present? && FeatureFlag.vexi.enabled?(:billing_cpwu_chatop_send_copilot_plan, chatop_user, default: false)
      block_kit_ui = chatop_user.present? && FeatureFlag.vexi.enabled?(:billing_cpwu_chatop_block_kit_ui, chatop_user, default: false)
      markdown_ui = chatop_user.present? && FeatureFlag.vexi.enabled?(:billing_cpwu_chatop_markdown_ui, chatop_user, default: false)

      # Build the parameters dynamically
      cpwu_params_hash = {
        customer_id: customer_id.to_s,
        product: product.to_s,
        sku: sku.to_s,
        repo_id: repo_id.presence.to_i,
        org_id: org_id.presence.to_i,
        actor_id: actor_id.presence.to_i,
        quantity: quantity.presence.to_f,
      }

      # Trust tier: existing customer-keyed flag stays untouched. CLI override wins.
      # Accept names (`trusted`/`neutral`/`untrusted`) or integers for back-compat.
      cpwu_params_hash[:trust_tier] =
        if trust_tier_override.present?
          parsed = parse_trust_tier_override(trust_tier_override)
          return chatop_send "Unknown trust_tier override `#{trust_tier_override}`. Valid: #{TRUST_TIER_NAME_TO_INT.keys.to_sentence} (or integer 1-3)" if parsed.nil?
          parsed
        elsif customer.present? && customer.billable_owner.present? && customer.billable_owner&.feature_flag_enabled?(:billing_can_proceed_with_usage_trust_tier, default: false)
          ::TrustTiers::Tier.for_billable_owner(customer.billable_owner).tier
        else
          0
        end

      # Copilot plan: only resolve/send when the actor-scoped flag is enabled.
      copilot_plan_int = nil
      if send_copilot_plan
        if copilot_plan_override.present? && !COPILOT_PLAN_NAME_TO_ENUM.key?(copilot_plan_override.downcase)
          return chatop_send "Unknown copilot_plan override `#{copilot_plan_override}`. Valid values: #{COPILOT_PLAN_NAME_TO_ENUM.keys.to_sentence}"
        end
        copilot_plan_int = resolve_copilot_plan_int(entity, customer, copilot_plan_override)
        cpwu_params_hash[:copilot_plan] = copilot_plan_int
      end

      cpwu_params = ::Billing::Platform::CanProceedWithUsage::RequestParams.new(cpwu_params_hash)
      unless cpwu_params.valid?
        return chatop_send "Please provide value(s) for #{cpwu_params.missing_keys.to_sentence}"
      end

      # Make API calls
      cpwu_response = ::Billing::Platform::CanProceedWithUsage.call(cpwu_params)
      customer_response = ::Billing::Platform::Api::Client.new.get_customer(customer_id: customer_id.to_s)

      ctx = {
        entity: entity,
        customer: customer,
        customer_id: customer_id,
        cpwu_params: cpwu_params,
        cpwu_response: cpwu_response,
        customer_response: customer_response,
        send_copilot_plan: send_copilot_plan,
        copilot_plan_int: copilot_plan_int,
      }

      if block_kit_ui
        render_cpwu_block_kit(ctx)
      elsif markdown_ui
        render_cpwu_markdown(ctx)
      else
        render_cpwu_legacy(ctx)
      end
    end

    private

    def render_cpwu_legacy(ctx)
      response = []

      if ctx[:entity]
        response << "✅ Billable Entity: #{ctx[:entity].display_login} (ID: #{ctx[:entity].id})"
      end

      if ctx[:customer].nil?
        response << "⚠️  Dotcom Customer #{ctx[:customer_id]} not found"
      else
        response << "✅ Dotcom Customer: #{ctx[:customer].name} (ID: #{ctx[:customer_id]})"
        response << "\t- Billed via Billing Platform: Yes"
      end

      customer_response = ctx[:customer_response]
      if customer_response.is_a?(::Billing::Platform::Api::Error)
        response << "❌ Error getting customer details: #{customer_response.message}"
      else
        customer_data = customer_response[:customer]
        billing_target_icon = customer_data[:billingTarget] == :Azure ? ":azure:" : ":zuora:"
        response << "✅ Billing Platform Customer details retrieved successfully"
        response << "\t- Billing Target: #{billing_target_icon} #{customer_data[:billingTarget]}"
        response << "\t- Azure Subscription ID: #{customer_data[:azureAccountId]}" if customer_data[:azureAccountId].present?
        response << "\t- Zuora Account Number: #{customer_data[:zuoraAccountNumber]}" if customer_data[:zuoraAccountNumber].present?
        response << "\t- Has Zuora Subscription: #{customer_data[:hasZuoraSubscription] ? "Yes" : "No"}"
        response << "\t- Has Payment Method: #{customer_data[:hasPaymentMethod] ? "Yes" : "No"}"
      end

      cpwu_response = ctx[:cpwu_response]
      if cpwu_response.error.present?
        response << "❌ Error checking 'canProceed': #{T.must(cpwu_response.error).message}"
      else
        response << "Can Proceed With Usage"
        response << (cpwu_response.can_proceed ? "✅ Usage CAN proceed" : "❌ Usage CANNOT proceed")

        pretty_json = JSON.pretty_generate(cpwu_response.serialize)
        response << "JSON Response\n"
        response << "```\n#{pretty_json}\n```"
      end

      chatop_send response.join("\n")
    end

    def render_cpwu_markdown(ctx)
      cpwu_params = ctx[:cpwu_params]
      cpwu_response = ctx[:cpwu_response]
      customer_response = ctx[:customer_response]

      lines = []
      lines << ":moneybag: *Can Proceed With Usage* — #{cpwu_status_line(cpwu_response)}"
      lines << ""

      lines << "*▶ Inputs sent*"
      lines << "  • Customer: `#{ctx[:customer]&.name || "(not found)"}` (`#{ctx[:customer_id]}`)"
      lines << "  • Billable Entity: `#{ctx[:entity].display_login}` (ID: `#{ctx[:entity].id}`)" if ctx[:entity]
      lines << "  • Product / SKU: `#{cpwu_params.product}` / `#{cpwu_params.sku}`"
      lines << "  • Trust Tier: *#{trust_tier_label(cpwu_params.trust_tier)}* (`#{cpwu_params.trust_tier}`)"
      lines << "  • Copilot Plan: *#{copilot_plan_label(ctx[:copilot_plan_int])}* (`#{ctx[:copilot_plan_int]}`)" if ctx[:send_copilot_plan]
      lines << "  • Repo / Org / Actor / Qty: `#{cpwu_params.repo_id}` / `#{cpwu_params.org_id}` / `#{cpwu_params.actor_id}` / `#{cpwu_params.quantity}`"
      lines << ""

      lines << "*◀ Response*"
      if cpwu_response.error.present?
        lines << "  • ❌ Error: `#{T.must(cpwu_response.error).message}`"
      else
        lines << "  • Status: `#{cpwu_response.status}`"
        lines << "  • Plan Name: `#{cpwu_response.plan_name.presence || "(none)"}`"
        lines << "  • Applicable Budgets: `#{cpwu_response.applicable_budgets.size}` · Plan Discounts: `#{cpwu_response.plan_discounts.size}`"
      end
      lines << ""

      lines << "*Billing Platform Customer*"
      if customer_response.is_a?(::Billing::Platform::Api::Error)
        lines << "  • ❌ Error: `#{customer_response.message}`"
      else
        customer_data = customer_response[:customer]
        billing_target_icon = customer_data[:billingTarget] == :Azure ? ":azure:" : ":zuora:"
        lines << "  • Billing Target: #{billing_target_icon} `#{customer_data[:billingTarget]}`"
        lines << "  • Azure Subscription ID: `#{customer_data[:azureAccountId]}`" if customer_data[:azureAccountId].present?
        lines << "  • Zuora Account Number: `#{customer_data[:zuoraAccountNumber]}`" if customer_data[:zuoraAccountNumber].present?
        lines << "  • Has Zuora Subscription: `#{customer_data[:hasZuoraSubscription] ? "Yes" : "No"}` · Has Payment Method: `#{customer_data[:hasPaymentMethod] ? "Yes" : "No"}`"
      end

      lines << ""
      lines << "```"
      lines << JSON.pretty_generate(cpwu_response.serialize)
      lines << "```"

      chatop_send lines.join("\n"), options: { thread_style: 1, color: cpwu_color(cpwu_response) }
    end

    def render_cpwu_block_kit(ctx)
      cpwu_response = ctx[:cpwu_response]
      customer_response = ctx[:customer_response]
      customer = ctx[:customer]
      cpwu_params = ctx[:cpwu_params]

      blocks = []
      blocks << { type: "header", text: { type: "plain_text", text: ":moneybag: Can Proceed With Usage", emoji: true } }
      blocks << { type: "context", elements: [{ type: "mrkdwn", text: cpwu_status_line(cpwu_response) }] }
      blocks << { type: "divider" }
      blocks << { type: "section", text: { type: "mrkdwn", text: "*▶ Inputs sent*" } }

      input_fields = []
      input_fields << field_pair("Customer", "#{customer&.name || "(not found)"}\n`#{ctx[:customer_id]}`")
      input_fields << field_pair("Billable Entity", ctx[:entity] ? "#{ctx[:entity].display_login}\n`#{ctx[:entity].id}`" : "_n/a_")
      input_fields << field_pair("Product", "`#{cpwu_params.product}`")
      input_fields << field_pair("SKU", "`#{cpwu_params.sku}`")
      input_fields << field_pair("Trust Tier", "*#{trust_tier_label(cpwu_params.trust_tier)}*\n`#{cpwu_params.trust_tier}`")
      input_fields << field_pair("Copilot Plan", "*#{copilot_plan_label(ctx[:copilot_plan_int])}*\n`#{ctx[:copilot_plan_int]}`") if ctx[:send_copilot_plan]
      input_fields << field_pair("Repo / Org / Actor", "`#{cpwu_params.repo_id}` / `#{cpwu_params.org_id}` / `#{cpwu_params.actor_id}`")
      input_fields << field_pair("Quantity", "`#{cpwu_params.quantity}`")

      # Slack supports max 10 fields per section block; split if necessary.
      input_fields.each_slice(10) do |slice|
        blocks << { type: "section", fields: slice }
      end

      blocks << { type: "divider" }
      blocks << { type: "section", text: { type: "mrkdwn", text: "*◀ Response*" } }

      if cpwu_response.error.present?
        blocks << { type: "section", text: { type: "mrkdwn", text: ":x: Error: `#{T.must(cpwu_response.error).message}`" } }
      else
        response_fields = [
          field_pair("Status", "`#{cpwu_response.status}`"),
          field_pair("Plan Name", "`#{cpwu_response.plan_name.presence || "(none)"}`"),
          field_pair("Applicable Budgets", "`#{cpwu_response.applicable_budgets.size}`"),
          field_pair("Plan Discounts", "`#{cpwu_response.plan_discounts.size}`"),
        ]
        blocks << { type: "section", fields: response_fields }
      end

      blocks << { type: "divider" }
      blocks << { type: "section", text: { type: "mrkdwn", text: "*Billing Platform Customer*" } }

      if customer_response.is_a?(::Billing::Platform::Api::Error)
        blocks << { type: "section", text: { type: "mrkdwn", text: ":x: Error: `#{customer_response.message}`" } }
      else
        customer_data = customer_response[:customer]
        billing_target_icon = customer_data[:billingTarget] == :Azure ? ":azure:" : ":zuora:"
        customer_fields = [
          field_pair("Billing Target", "#{billing_target_icon} `#{customer_data[:billingTarget]}`"),
          field_pair("Has Zuora Subscription", customer_data[:hasZuoraSubscription] ? "Yes" : "No"),
          field_pair("Has Payment Method", customer_data[:hasPaymentMethod] ? "Yes" : "No"),
        ]
        customer_fields << field_pair("Azure Subscription ID", "`#{customer_data[:azureAccountId]}`") if customer_data[:azureAccountId].present?
        customer_fields << field_pair("Zuora Account Number", "`#{customer_data[:zuoraAccountNumber]}`") if customer_data[:zuoraAccountNumber].present?
        blocks << { type: "section", fields: customer_fields }
      end

      blocks << { type: "divider" }
      blocks << { type: "section", text: { type: "mrkdwn", text: truncated_json_block(cpwu_response.serialize) } }
      blocks << { type: "context", elements: [{ type: "mrkdwn", text: ":memo: invoked by `@#{params[:user]}` · <https://github.com/github/billing-platform/blob/main/docs/reference/features/can-proceed-with-usage.md|docs>" }] }

      payload = {
        attachments: [{
          color: cpwu_color(cpwu_response),
          blocks: blocks,
        }],
        text: "Can Proceed With Usage: #{cpwu_status_text(cpwu_response)}",
      }

      render_chatop_result(payload, options: { thread_style: 1 })
    end

    # The chatops-controller gem's chatop_send coerces its message to a String
    # and strips :result from options. Block Kit / rich-object responses need
    # `result` to be a Hash, so we use the gem's lower-level jsonrpc_response
    # helper to stay aligned with future gem changes.
    def render_chatop_result(result, options: {})
      jsonrpc_response({ result: result }.merge(options.except(:result)))
    end

    def cpwu_status_line(cpwu_response)
      if cpwu_response.error.present?
        ":x: Error checking 'canProceed': `#{T.must(cpwu_response.error).message}`"
      elsif cpwu_response.can_proceed
        ":white_check_mark: Usage CAN proceed · `#{cpwu_response.status}`"
      else
        ":x: Usage CANNOT proceed · `#{cpwu_response.status}`"
      end
    end

    def cpwu_status_text(cpwu_response)
      return "error" if cpwu_response.error.present?
      cpwu_response.can_proceed ? "CAN proceed" : "CANNOT proceed"
    end

    def cpwu_color(cpwu_response)
      return SLACK_COLOR_RED if cpwu_response.error.present?
      cpwu_response.can_proceed ? SLACK_COLOR_GREEN : SLACK_COLOR_YELLOW
    end

    def trust_tier_label(tier)
      ::TrustTiers::Tier.tier_name(tier) || "TIER_#{tier}"
    end

    # Returns the integer for a `trust_tier:` CLI override, or nil if invalid.
    # Accepts the human names from TRUST_TIER_NAME_TO_INT and any "1".."3".
    def parse_trust_tier_override(raw)
      return TRUST_TIER_NAME_TO_INT[raw.downcase] if TRUST_TIER_NAME_TO_INT.key?(raw.downcase)
      return raw.to_i if raw.match?(/\A[1-3]\z/)
      nil
    end

    def copilot_plan_label(int)
      COPILOT_PLAN_NAME_TO_ENUM.key(int)&.upcase || "PLAN_#{int}"
    end

    def field_pair(label, value)
      { type: "mrkdwn", text: "*#{label}*\n#{value}" }
    end

    # Slack section block text has a 3000-character limit. JSON dumps with
    # many budgets/discounts can exceed it, so truncate with a clear marker.
    SLACK_SECTION_TEXT_LIMIT = 3000
    JSON_FENCE_OVERHEAD = "```\n```".length

    def truncated_json_block(payload)
      pretty = JSON.pretty_generate(payload)
      max_body = SLACK_SECTION_TEXT_LIMIT - JSON_FENCE_OVERHEAD
      if pretty.length > max_body
        marker = "\n…[truncated; #{pretty.length - max_body} chars omitted]"
        pretty = pretty.byteslice(0, max_body - marker.length).to_s + marker
      end
      "```\n#{pretty}\n```"
    end

    # Resolves the copilot plan integer to send on the CPWU request. Priority:
    # 1. CLI override (`copilot_plan:NAME`)
    # 2. Entity-driven resolution via copilot_plan_enum (+ edu detection)
    # 3. UNKNOWN (0)
    #
    # Note: individual TRIAL is not auto-detected here — `Copilot::Plans::CFI`
    # collapses trial state into the base plan. Use `copilot_plan:individual_trial`
    # explicitly to test that case.
    def resolve_copilot_plan_int(entity, customer, override)
      if override.present?
        return COPILOT_PLAN_NAME_TO_ENUM.fetch(override.downcase, 0)
      end

      target = entity || customer&.billable_owner
      resolve_target_plan_int(target)
    end

    def resolve_target_plan_int(target)
      case target
      when ::Business
        plan_enum_to_billing_platform_int(::Copilot::Business.new(target).copilot_plan_enum)
      when ::Organization
        plan_enum_to_billing_platform_int(::Copilot::Organization.new(target).copilot_plan_enum)
      when ::User
        resolve_user_plan_int(target)
      else
        0
      end
    rescue StandardError => e
      Failbot.report(e,
        "code.namespace": self.class.name,
        "code.function": "resolve_target_plan_int",
        "gh.target.class": target&.class&.name,
      )
      0
    end

    def resolve_user_plan_int(user)
      public_user = ::Copilot::Public::User.for(user)
      return 8 if public_user.has_educational_access? # INDIVIDUAL_EDU
      plan_enum_to_billing_platform_int(public_user.copilot_plan_enum)
    end

    def plan_enum_to_billing_platform_int(plan_enum)
      case plan_enum
      when ::Copilot::Plans::CFI::Free then 4
      when ::Copilot::Plans::CFI::Pro then 3
      when ::Copilot::Plans::CFI::ProPlus then 7
      when ::Copilot::Plans::CFI::Max then 9
      when ::Copilot::Plans::CFB::Business,
           ::Copilot::Plans::CFB::StandaloneBusiness,
           ::Copilot::Plans::CFB::NonStandaloneBusiness then 1
      when ::Copilot::Plans::CFB::Enterprise then 2
      else 0
      end
    end
  end
end
