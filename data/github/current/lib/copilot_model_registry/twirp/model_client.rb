# typed: strict
# frozen_string_literal: true

require "monolith-twirp-copilot-registry"
require_relative "dev_client"

module CopilotModelRegistry
  module Twirp
    class ModelClient < CopilotModelRegistry::Twirp::BaseClient
      include GitHub::Memoizer

      sig { returns(T::Boolean) }
      def self.dev_mode?
        Rails.env.development? && !GitHub.enterprise?
      end

      sig { returns(T.nilable(CopilotModelRegistry::Twirp::DevClient)) }
      def dev_client
        return nil unless self.class.dev_mode?

        @dev_client ||= T.let(CopilotModelRegistry::Twirp::DevClient.new, T.nilable(CopilotModelRegistry::Twirp::DevClient))
      end

      # This method calls the limiter and gets the consumptive user stuff
      sig { returns(T::Array[CopilotModel]) }
      def get_models
        GitHub.logger.with_named_tags({
          "code.function": "get_models",
          "code.namespace": "CopilotModelRegistry::Twirp::ModelRegistryClient",
        }) do
          use_db = use_db_registry?
          rpc_method = use_db ? :GetModelsDB : :GetModels
          method_tag = use_db ? "get_models_db" : "get_models"

          GitHub.logger.info("Getting models from Copilot Model Registry via Twirp",
            "gh.copilot_model_registry.rpc_method": rpc_method.to_s)

          response = rpc(rpc_method, {})

          GitHub.logger.info(
            "Finished Twirp Call",
            "gh.copilot_model_registry.response.status": response&.status,
            "gh.copilot_model_registry.response.call_succeeded": response&.call_succeeded,
          )

          if response&.call_succeeded?
            GitHub.dogstats.increment("copilot_model_registry.model_client.success", tags: { method: method_tag })
            parse_models_response(response.value)
          else
            failbot_report(response&.status || CopilotModelRegistry::Twirp::Error.new("Twirp call failed for #{rpc_method}"))
            GitHub.dogstats.increment("copilot_model_registry.model_client.failure", tags: { method: method_tag, status: response.status })
            GitHub.logger.info("Failed to get models call")
            []
          end
        end
      end

      # List all YAML models (summaries)
      sig { params(include_deleted: T::Boolean).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def list_yaml_models(include_deleted: false)
        dc = dev_client; return dc.list_yaml_models(include_deleted: include_deleted) if dc

        response = yaml_rpc(:ListYAMLModels, "list_yaml_models", { include_deleted: include_deleted })
        return [] unless response

        response.models.map do |model|
          {
            reference_id: model.reference_id,
            name: model.name,
            version: model.version,
            vendor: model.vendor,
            model_availability: model.model_availability,
            state: model.state,
            updated_at: model.updated_at&.to_time,
            updated_by: model.updated_by,
          }
        end
      end

      # Get a single YAML model's full content
      sig { params(reference_id: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def get_yaml_model(reference_id)
        dc = dev_client; return dc.get_yaml_model(reference_id) if dc

        response = yaml_rpc(:GetYAMLModel, "get_yaml_model", { reference_id: reference_id })
        return nil unless response

        {
          reference_id: response.reference_id,
          yaml_content: response.yaml_content,
          state: response.state,
          created_at: response.created_at&.to_time,
          updated_at: response.updated_at&.to_time,
          updated_by: response.updated_by,
        }
      end

      # Create a new YAML model
      sig { params(yaml_content: String, actor: String).returns(T::Hash[Symbol, T.untyped]) }
      def create_yaml_model(yaml_content:, actor:)
        dc = dev_client; return dc.create_yaml_model(yaml_content: yaml_content, actor: actor) if dc

        response = yaml_rpc(:CreateYAMLModel, "create_yaml_model", { yaml_content: yaml_content, actor: actor })
        return { valid: false, validation_errors: [{ field: "", message: "RPC call failed: #{last_rpc_error}", severity: "error" }] } unless response

        {
          reference_id: response.reference_id,
          yaml_content: response.yaml_content,
          valid: response.valid,
          validation_errors: parse_validation_errors(response.validation_errors),
        }
      end

      # Update an existing YAML model
      sig { params(reference_id: String, yaml_content: String, actor: String).returns(T::Hash[Symbol, T.untyped]) }
      def update_yaml_model(reference_id:, yaml_content:, actor:)
        dc = dev_client; return dc.update_yaml_model(reference_id: reference_id, yaml_content: yaml_content, actor: actor) if dc

        response = yaml_rpc(:UpdateYAMLModel, "update_yaml_model", { reference_id: reference_id, yaml_content: yaml_content, actor: actor })
        return { valid: false, validation_errors: [{ field: "", message: "RPC call failed: #{last_rpc_error}", severity: "error" }] } unless response

        {
          reference_id: response.reference_id,
          yaml_content: response.yaml_content,
          valid: response.valid,
          validation_errors: parse_validation_errors(response.validation_errors),
        }
      end

      # Delete a YAML model
      sig { params(reference_id: String, actor: String).returns(T::Boolean) }
      def delete_yaml_model(reference_id:, actor:)
        dc = dev_client; return dc.delete_yaml_model(reference_id: reference_id, actor: actor) if dc

        response = yaml_rpc(:DeleteYAMLModel, "delete_yaml_model", { reference_id: reference_id, actor: actor })
        !response.nil?
      end

      # Restore a soft-deleted YAML model
      sig { params(reference_id: String, actor: String).returns(T::Boolean) }
      def restore_yaml_model(reference_id:, actor:)
        dc = dev_client; return dc.restore_yaml_model(reference_id: reference_id, actor: actor) if dc

        response = yaml_rpc(:RestoreYAMLModel, "restore_yaml_model", { reference_id: reference_id, actor: actor })
        !response.nil?
      end

      # Hard-delete ALL YAML models and history from the database.
      sig { params(actor: String).returns(T::Boolean) }
      def delete_yaml_db_content(actor:)
        dc = dev_client; return dc.delete_yaml_db_content(actor: actor) if dc

        response = yaml_rpc(:DeleteYAMLDbContent, "delete_yaml_db_content", { reference_id: "", actor: actor })
        !response.nil?
      end

      # Publish a draft YAML model
      sig { params(reference_id: String, actor: String).returns(T::Boolean) }
      def publish_yaml_model(reference_id:, actor:)
        dc = dev_client; return dc.publish_yaml_model(reference_id: reference_id, actor: actor) if dc

        response = yaml_rpc(:PublishYAMLModelByReferenceID, "publish_yaml_model_by_reference_id", { reference_id: reference_id, actor: actor })
        !response.nil?
      end

      # Validate YAML without persisting
      sig { params(yaml_content: String, reference_id: String).returns(T::Hash[Symbol, T.untyped]) }
      def validate_yaml_model(yaml_content:, reference_id: "")
        dc = dev_client; return dc.validate_yaml_model(yaml_content: yaml_content, reference_id: reference_id) if dc

        response = yaml_rpc(:ValidateYAMLModel, "validate_yaml_model", { yaml_content: yaml_content, reference_id: reference_id })
        return { valid: false, validation_errors: [{ field: "", message: "RPC call failed: #{last_rpc_error}", severity: "error" }] } unless response

        {
          valid: response.valid,
          validation_errors: parse_validation_errors(response.validation_errors),
        }
      end

      # Get full model details including all feature flags for SIMSHIP instructions
      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def get_models_full
        dc = dev_client; return dc.get_models_full if dc

        GitHub.logger.with_named_tags({
          "code.function": "get_models_full",
          "code.namespace": "CopilotModelRegistry::Twirp::ModelRegistryClient",
        }) do
          use_db = use_db_registry?
          rpc_method = use_db ? :GetModelsDB : :GetModels
          method_tag = use_db ? "get_models_full_db" : "get_models_full"

          GitHub.logger.info("Getting full model details from Copilot Model Registry via Twirp",
            "gh.copilot_model_registry.rpc_method": rpc_method.to_s)

          response = rpc(rpc_method, {})

          GitHub.logger.info(
            "Finished Twirp Call",
            "gh.copilot_model_registry.response.status": response&.status,
            "gh.copilot_model_registry.response.call_succeeded": response&.call_succeeded,
          )

          if response&.call_succeeded?
            GitHub.dogstats.increment("copilot_model_registry.model_client.success", tags: { method: method_tag })
            parse_models_full_response(response.value)
          else
            failbot_report(response&.status || CopilotModelRegistry::Twirp::Error.new("Twirp call failed for #{rpc_method}"))
            GitHub.dogstats.increment("copilot_model_registry.model_client.failure", tags: { method: method_tag, status: response.status })
            GitHub.logger.info("Failed to get models call")
            []
          end
        end
      end

      # Submit a model change for peer review
      sig { params(yaml_content: String, target_state: String, actor: String, reference_id: String).returns(T::Hash[Symbol, T.untyped]) }
      def submit_yaml_model_change(yaml_content:, target_state:, actor:, reference_id: "")
        dc = dev_client; return dc.submit_yaml_model_change(yaml_content: yaml_content, target_state: target_state, actor: actor, reference_id: reference_id) if dc

        response = yaml_rpc(:SubmitYAMLModelChange, "submit_yaml_model_change", {
          yaml_content: yaml_content,
          target_state: target_state,
          actor: actor,
          reference_id: reference_id,
        })
        return { valid: false, validation_errors: [{ field: "", message: "RPC call failed: #{last_rpc_error}", severity: "error" }] } unless response

        {
          pending_change: parse_pending_change(response.pending_change),
          valid: response.valid,
          validation_errors: parse_validation_errors(response.validation_errors),
        }
      end

      # List pending changes, optionally filtered by reference_id and/or status
      sig { params(reference_id: String, status: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def list_pending_changes(reference_id: "", status: "pending")
        dc = dev_client; return dc.list_pending_changes(reference_id: reference_id, status: status) if dc

        response = yaml_rpc(:ListPendingChanges, "list_pending_changes", { reference_id: reference_id, status: status })
        return [] unless response

        response.pending_changes.map { |pc| parse_pending_change(pc) }
      end

      # Get a single pending change by ID
      sig { params(id: Integer).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def get_pending_change(id:)
        dc = dev_client; return dc.get_pending_change(id: id) if dc

        response = yaml_rpc(:GetPendingChange, "get_pending_change", { id: id })
        return nil unless response

        parse_pending_change(response.pending_change)
      end

      # Approve a pending change (reviewer must differ from submitter)
      sig { params(pending_change_id: Integer, actor: String, comment: String).returns(T::Hash[Symbol, T.untyped]) }
      def approve_yaml_model_change(pending_change_id:, actor:, comment: "")
        dc = dev_client; return dc.approve_yaml_model_change(pending_change_id: pending_change_id, actor: actor, comment: comment) if dc

        response = yaml_rpc(:ApproveYAMLModelChange, "approve_yaml_model_change", {
          pending_change_id: pending_change_id,
          actor: actor,
          comment: comment,
        })
        return { success: false, error_message: "RPC call failed: #{last_rpc_error}" } unless response

        {
          success: response.success,
          error_message: response.error_message,
          validation_errors: parse_validation_errors(response.validation_errors),
        }
      end

      # Reject a pending change (reviewer must differ from submitter)
      sig { params(pending_change_id: Integer, actor: String, comment: String).returns(T::Hash[Symbol, T.untyped]) }
      def reject_yaml_model_change(pending_change_id:, actor:, comment: "")
        dc = dev_client; return dc.reject_yaml_model_change(pending_change_id: pending_change_id, actor: actor, comment: comment) if dc

        response = yaml_rpc(:RejectYAMLModelChange, "reject_yaml_model_change", {
          pending_change_id: pending_change_id,
          actor: actor,
          comment: comment,
        })
        return { success: false, error_message: "RPC call failed: #{last_rpc_error}" } unless response

        {
          success: response.success,
          error_message: response.error_message,
        }
      end

      # Request AI review for a pending change
      sig { params(pending_change_id: Integer, actor: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def request_ai_review(pending_change_id:, actor:)
        dc = dev_client; return dc.request_ai_review(pending_change_id: pending_change_id, actor: actor) if dc

        response = yaml_rpc(:RequestAIReview, "request_ai_review", {
          pending_change_id: pending_change_id,
          actor: actor,
        })
        return nil unless response

        parse_ai_review(response.ai_review)
      end

      # Get history entries for a model
      sig { params(reference_id: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def get_yaml_model_history(reference_id:)
        dc = dev_client; return dc.get_yaml_model_history(reference_id: reference_id) if dc

        response = yaml_rpc(:GetYAMLModelHistory, "get_yaml_model_history", { reference_id: reference_id })
        return [] unless response

        response.entries.map do |entry|
          {
            id: entry.id,
            yaml_model_id: entry.yaml_model_id,
            reference_id: entry.reference_id,
            action: entry.action,
            actor: entry.actor,
            json_content_before: entry.json_content_before,
            json_content_after: entry.json_content_after,
            created_at: entry.created_at&.to_time,
          }
        end
      end

      private

      sig { returns(T::Boolean) }
      def use_db_registry?
        FeatureFlag.vexi.enabled?(:copilot_use_db_model_registry, default: false)
      end

      sig { returns(T.class_of(::MonolithTwirp::Copilot::Registry::V1::CopilotRegistryAPIClient)) }
      def twirp_class
        ::MonolithTwirp::Copilot::Registry::V1::CopilotRegistryAPIClient
      end

      sig { params(method: Symbol, metric_name: String, params: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
      def yaml_rpc(method, metric_name, params)
        GitHub.logger.info("Calling #{method} on Copilot Model Registry")
        response = rpc(method, params)

        if response&.call_succeeded?
          GitHub.dogstats.increment("copilot_model_registry.model_client.success", tags: { method: metric_name })
          response.value
        else
          @last_rpc_error = T.let(
            if response.nil?
              "Service unreachable or request timed out"
            else
              response.options&.dig(:message) || "Unknown error (status: #{response.status})"
            end,
            T.nilable(String),
          )
          failbot_report(response&.status || CopilotModelRegistry::Twirp::Error.new("Twirp call failed for #{method}"))
          GitHub.dogstats.increment("copilot_model_registry.model_client.failure", tags: { method: metric_name, status: response&.status })
          GitHub.logger.info("Failed #{method} call: #{@last_rpc_error}")
          nil
        end
      end

      sig { returns(T.nilable(String)) }
      def last_rpc_error
        @last_rpc_error
      end

      sig { params(errors: T.untyped).returns(T::Array[T::Hash[Symbol, String]]) }
      def parse_validation_errors(errors)
        return [] if errors.nil?

        errors.map do |err|
          {
            field: err.field,
            message: err.message,
            severity: err.severity,
          }
        end
      end

      sig { params(pc: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
      def parse_pending_change(pc)
        return {} if pc.nil?

        {
          id: pc.id,
          yaml_model_id: pc.yaml_model_id,
          reference_id: pc.reference_id,
          target_state: pc.target_state,
          yaml_content_pending: pc.yaml_content_pending,
          yaml_content_current: pc.yaml_content_current,
          submitted_by: pc.submitted_by,
          submitted_at: pc.submitted_at&.to_time,
          status: pc.status,
          reviewed_by: pc.reviewed_by,
          reviewed_at: pc.reviewed_at&.to_time,
          review_comment: pc.review_comment,
          ai_reviews: (pc.ai_reviews || []).map { |r| parse_ai_review(r) },
          created_at: pc.created_at&.to_time,
          updated_at: pc.updated_at&.to_time,
        }
      end

      sig { params(review: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
      def parse_ai_review(review)
        return {} if review.nil?

        {
          id: review.id,
          pending_change_id: review.pending_change_id,
          reference_id: review.reference_id,
          ai_feedback: review.ai_feedback,
          prompt_used: review.prompt_used,
          requested_by: review.requested_by,
          created_at: review.created_at&.to_time,
        }
      end

      # Typed hash representing a parsed model
      CopilotModel = T.type_alias do
        {
          key: String,
          name: String,
          description: String,
          plans: T::Array[String],
          feature_flag: String,
          internal: T::Boolean,
          preview: T::Boolean,
          documentation_link: String,
          documentation_link_text: String,
          inline_approval_enabled: T::Boolean,
          policy_pro_feature_flag: String,
          policy_ga_feature_flag: String,
          policy_rollout_complete_feature_flag: String,
          vendor: String,
        }
      end

      sig do
        params(
          response: T.any(
            MonolithTwirp::Copilot::Registry::V1::GetModelsResponse,
            MonolithTwirp::Copilot::Registry::V1::GetModelsDBResponse
          )
        ).returns(T::Array[CopilotModel])
      end
      def parse_models_response(response)
        model_details = response.model_details
        models = T.let(
          model_details.map do |model|
            {
              key: model.policy_id,
              name: model.name,
              description: "A #{model.vendor} model. Version: #{model.version}.", # customize as needed
              plans: model.billing.restricted_to,
              feature_flag: model.feature_flag,
              internal: !model.is_model_picker_enabled,
              preview: model.is_preview,
              documentation_link: model.documentation_link,
              documentation_link_text: model.documentation_link_text,
              inline_approval_enabled: model.inline_approval&.enabled || false,
              policy_pro_feature_flag: model.policy_pro_feature_flag,
              policy_ga_feature_flag: model.policy_ga_feature_flag,
              policy_rollout_complete_feature_flag: model.policy_rollout_complete_feature_flag,
              vendor: model.vendor,
            }
          end,
          T::Array[CopilotModel]
        )
        models.freeze
      end

      sig do
        params(
          response: T.any(
            MonolithTwirp::Copilot::Registry::V1::GetModelsResponse,
            MonolithTwirp::Copilot::Registry::V1::GetModelsDBResponse
          )
        ).returns(T::Array[T::Hash[Symbol, T.untyped]])
      end
      def parse_models_full_response(response)
        model_details = response.model_details
        model_details.map do |model|
          # Extract visible feature flags
          visible_flags = model.visible_feature_flag_checks.map do |check|
            {
              flag_name: check.flag_name,
              conditions: {
                requires_valid_hmac: check.conditions&.requires_valid_hmac || false,
                integrations_allow_list: check.conditions&.integrations_allow_list&.to_a || [],
                integration_categories_allow_list: check.conditions&.integration_categories_allow_list&.to_a || [],
                sku_allow_list: check.conditions&.sku_allow_list&.to_a || [],
              }
            }
          end

          # Extract endpoint feature flags
          endpoint_flags = model.endpoints.map { |endpoint| endpoint.feature_flag }.compact.uniq

          {
            key: model.policy_id,
            name: model.name,
            description: "A #{model.vendor} model. Version: #{model.version}.",
            plans: model.billing.restricted_to.to_a,
            feature_flag: model.feature_flag,
            internal: !model.is_model_picker_enabled,
            preview: model.is_preview,
            documentation_link: model.documentation_link,
            documentation_link_text: model.documentation_link_text,
            inline_approval_enabled: model.inline_approval&.enabled || false,
            policy_pro_feature_flag: model.policy_pro_feature_flag,
            policy_ga_feature_flag: model.policy_ga_feature_flag,
            policy_rollout_complete_feature_flag: model.policy_rollout_complete_feature_flag,
            vendor: model.vendor,
            version: model.version,
            reference_id: model.reference_id,
            inline_approval_terms: model.inline_approval&.terms || "",
            skip_policy_feature_flag: model.skip_policy_feature_flag || "",
            retry_feature_flag: model.retry_feature_flag || "",
            warning_message_high_usage_ff: model.warning_message_feature_flags&.feature_flag_warning_message_high_usage || "",
            warning_message_degraded_performance_ff: model.warning_message_feature_flags&.feature_flag_warning_message_degraded_performance || "",
            warning_message_degraded_performance_provider_ff: model.warning_message_feature_flags&.feature_flag_warning_message_degraded_performance_provider || "",
            visible_feature_flags: visible_flags,
            endpoint_feature_flags: endpoint_flags,
          }
        end
      end
    end
  end
end
