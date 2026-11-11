# typed: strict
# frozen_string_literal: true

require "yaml"
require "json"
require "fileutils"

module CopilotModelRegistry
  module Twirp
    # Development-mode client that reads/writes YAML files from disk instead of
    # calling the remote copilot-model-registry Twirp service.
    # Activated when Rails.env.development? && !GitHub.enterprise?
    class DevClient
      FIXTURES_DIR = T.let(
        File.expand_path("../dev_fixtures", __dir__).freeze,
        String,
      )

      PENDING_CHANGES_DIR = T.let(
        Rails.root.join("dev_fixtures", "pending_changes").to_s.freeze,
        String,
      )

      sig { void }
      def initialize
        FileUtils.mkdir_p(FIXTURES_DIR)
        FileUtils.mkdir_p(PENDING_CHANGES_DIR)
      end

      sig { params(include_deleted: T::Boolean).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def list_yaml_models(include_deleted: false)
        yaml_files.map do |path|
          data = load_yaml(path)
          meta = load_meta(path)
          {
            reference_id: data["referenceID"].to_s,
            name: data["name"].to_s,
            version: data["version"].to_s,
            vendor: data["vendor"].to_s,
            model_availability: data["modelAvailability"].to_s,
            state: "active",
            updated_at: File.mtime(path),
            updated_by: meta["actor"].to_s,
          }
        end
      end

      sig { params(reference_id: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def get_yaml_model(reference_id)
        path = file_path(reference_id)
        return nil unless File.exist?(path)

        meta = load_meta(path)
        {
          reference_id: reference_id,
          yaml_content: File.read(path),
          state: "active",
          created_at: File.ctime(path),
          updated_at: File.mtime(path),
          updated_by: meta["actor"].to_s,
        }
      end

      sig { params(yaml_content: String, actor: String).returns(T::Hash[Symbol, T.untyped]) }
      def create_yaml_model(yaml_content:, actor:)
        validation = validate_yaml_model(yaml_content: yaml_content)
        return validation unless validation[:valid]

        data = YAML.safe_load(yaml_content)
        ref_id = data["referenceID"].to_s
        path = file_path(ref_id)

        if File.exist?(path)
          return {
            valid: false,
            validation_errors: [{ field: "referenceID", message: "Model '#{ref_id}' already exists", severity: "error" }],
          }
        end

        File.write(path, yaml_content)
        save_meta(path, actor)
        {
          reference_id: ref_id,
          yaml_content: yaml_content,
          valid: true,
          validation_errors: [],
        }
      end

      sig { params(reference_id: String, yaml_content: String, actor: String).returns(T::Hash[Symbol, T.untyped]) }
      def update_yaml_model(reference_id:, yaml_content:, actor:)
        validation = validate_yaml_model(yaml_content: yaml_content)
        return validation unless validation[:valid]

        path = file_path(reference_id)
        File.write(path, yaml_content)
        save_meta(path, actor)
        {
          reference_id: reference_id,
          yaml_content: yaml_content,
          valid: true,
          validation_errors: [],
        }
      end

      sig { params(reference_id: String, actor: String).returns(T::Boolean) }
      def delete_yaml_model(reference_id:, actor:)
        path = file_path(reference_id)
        return false unless File.exist?(path)

        File.delete(path)
        meta_path = "#{path}.meta.json"
        File.delete(meta_path) if File.exist?(meta_path)
        true
      end

      sig { params(actor: String).returns(T::Boolean) }
      def delete_yaml_db_content(actor:)
        yaml_files.each do |path|
          File.delete(path)
          meta_path = "#{path}.meta.json"
          File.delete(meta_path) if File.exist?(meta_path)
        end
        true
      end

      sig { params(reference_id: String, actor: String).returns(T::Boolean) }
      def restore_yaml_model(reference_id:, actor:)
        false
      end

      sig { params(reference_id: String, actor: String).returns(T::Boolean) }
      def publish_yaml_model(reference_id:, actor:)
        path = file_path(reference_id)
        File.exist?(path)
      end

      sig { params(yaml_content: String, reference_id: String).returns(T::Hash[Symbol, T.untyped]) }
      def validate_yaml_model(yaml_content:, reference_id: "")
        errors = T.let([], T::Array[T::Hash[Symbol, String]])

        begin
          data = YAML.safe_load(yaml_content)
        rescue Psych::SyntaxError => e
          return {
            valid: false,
            validation_errors: [{ field: "", message: "Invalid YAML syntax: #{e.message}", severity: "error" }],
          }
        end

        unless data.is_a?(Hash)
          return {
            valid: false,
            validation_errors: [{ field: "", message: "YAML must be a mapping (Hash), got #{data.class}", severity: "error" }],
          }
        end

        # Required fields
        %w[referenceID name vendor].each do |field|
          if data[field].blank?
            errors << { field: field, message: "#{field} is required", severity: "error" }
          end
        end

        # Validate billing
        if data["billing"].is_a?(Hash) && data["billing"]["restrictedTo"].is_a?(Array)
          valid_plans = %w[free pro edu pro_plus business enterprise max]
          data["billing"]["restrictedTo"].each do |plan|
            unless valid_plans.include?(plan)
              errors << { field: "billing.restrictedTo", message: "Unknown plan '#{plan}'", severity: "warning" }
            end
          end
        end

        # Validate endpoints
        if data["endpoints"].is_a?(Array)
          data["endpoints"].each_with_index do |ep, idx|
            if ep["name"].blank?
              errors << { field: "endpoints[#{idx}].name", message: "Endpoint name is required", severity: "error" }
            end
            if ep["provider"].blank?
              errors << { field: "endpoints[#{idx}].provider", message: "Endpoint provider is required", severity: "error" }
            end
          end
        end

        {
          valid: errors.empty?,
          validation_errors: errors,
        }
      end

      # Pass-through methods for the original GetModels-based API (used by existing pages)

      sig { returns(T::Array[T.untyped]) }
      def get_models
        []
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def get_models_full
        yaml_files.map do |path|
          data = load_yaml(path)
          build_full_model_hash(data, path)
        end
      end

      # --- Review workflow methods (file-backed persistence in dev mode) ---

      sig { params(yaml_content: String, target_state: String, actor: String, reference_id: String).returns(T::Hash[Symbol, T.untyped]) }
      def submit_yaml_model_change(yaml_content:, target_state:, actor:, reference_id: "")
        validation = validate_yaml_model(yaml_content: yaml_content, reference_id: reference_id)
        parsed = YAML.safe_load(yaml_content) rescue nil
        resolved_ref = reference_id.presence || (parsed.is_a?(Hash) ? parsed["referenceID"].to_s : "")

        # Enforce one pending change per model
        existing = load_all_pending_changes.find { |c| c[:reference_id] == resolved_ref && c[:status] == "pending" }
        if existing
          return {
            pending_change: existing,
            valid: false,
            validation_errors: [{ field: "reference_id", message: "A pending change already exists for '#{resolved_ref}'. Please review or withdraw it first.", severity: "error" }],
          }
        end

        pending_change = {
          id: next_pending_change_id,
          yaml_model_id: nil,
          reference_id: resolved_ref,
          target_state: target_state,
          yaml_content_pending: yaml_content,
          yaml_content_current: reference_id.present? ? get_yaml_model(reference_id)&.dig(:yaml_content) : "",
          submitted_by: actor,
          submitted_at: Time.now.iso8601,
          status: "pending",
          reviewed_by: "",
          reviewed_at: nil,
          review_comment: nil,
          ai_reviews: [],
          created_at: Time.now.iso8601,
          updated_at: Time.now.iso8601,
        }

        if validation[:valid]
          save_pending_change(pending_change)
        end

        {
          pending_change: pending_change,
          valid: validation[:valid],
          validation_errors: validation[:validation_errors] || [],
        }
      end

      sig { params(reference_id: String, status: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def list_pending_changes(reference_id: "", status: "pending")
        changes = load_all_pending_changes
        changes = changes.select { |c| c[:status] == status } if status.present?
        changes = changes.select { |c| c[:reference_id] == reference_id } if reference_id.present?
        changes.sort_by { |c| c[:created_at].to_s }.reverse
      end

      sig { params(id: Integer).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def get_pending_change(id:)
        load_all_pending_changes.find { |c| c[:id] == id }
      end

      sig { params(pending_change_id: Integer, actor: String, comment: String).returns(T::Hash[Symbol, T.untyped]) }
      def approve_yaml_model_change(pending_change_id:, actor:, comment: "")
        change = get_pending_change(id: pending_change_id)
        return { success: false, error_message: "Pending change not found", validation_errors: [] } unless change
        return { success: false, error_message: "You cannot approve your own change", validation_errors: [] } if change[:submitted_by] == actor

        change[:status] = "approved"
        change[:reviewed_by] = actor
        change[:reviewed_at] = Time.now.iso8601
        change[:review_comment] = comment.presence
        change[:updated_at] = Time.now.iso8601
        save_pending_change(change)

        # Apply the change in dev mode
        ref = change[:reference_id].to_s
        if ref.present? && change[:yaml_content_pending].present?
          if change[:target_state] == "published"
            publish_yaml_model(reference_id: ref, actor: actor)
          elsif File.exist?(file_path(ref))
            update_yaml_model(reference_id: ref, yaml_content: change[:yaml_content_pending], actor: actor)
          else
            create_yaml_model(yaml_content: change[:yaml_content_pending], actor: actor)
          end
        end

        { success: true, error_message: "", validation_errors: [] }
      end

      sig { params(pending_change_id: Integer, actor: String, comment: String).returns(T::Hash[Symbol, T.untyped]) }
      def request_changes(pending_change_id:, actor:, comment: "")
        change = get_pending_change(id: pending_change_id)
        return { success: false, error_message: "Pending change not found" } unless change
        return { success: false, error_message: "You cannot request changes on your own submission" } if change[:submitted_by] == actor

        change[:reviewed_by] = actor
        change[:reviewed_at] = Time.now.iso8601
        change[:review_comment] = comment.presence
        change[:updated_at] = Time.now.iso8601
        # Keep status as "pending" — request changes does NOT remove from pending
        save_pending_change(change)

        { success: true, error_message: "" }
      end

      # Legacy method name kept for compatibility with Twirp proto
      sig { params(pending_change_id: Integer, actor: String, comment: String).returns(T::Hash[Symbol, T.untyped]) }
      def reject_yaml_model_change(pending_change_id:, actor:, comment: "")
        request_changes(pending_change_id: pending_change_id, actor: actor, comment: comment)
      end

      # Add a standalone review comment (no state change)
      sig { params(pending_change_id: Integer, actor: String, comment: String).returns(T::Hash[Symbol, T.untyped]) }
      def add_review_comment(pending_change_id:, actor:, comment:)
        change = get_pending_change(id: pending_change_id)
        return { success: false, error_message: "Pending change not found" } unless change

        review_comment = {
          id: Time.now.to_i,
          pending_change_id: pending_change_id,
          actor: actor,
          comment: comment,
          created_at: Time.now.iso8601,
        }

        change[:review_comments] = (change[:review_comments] || []) + [review_comment]
        change[:updated_at] = Time.now.iso8601
        save_pending_change(change)

        { success: true, error_message: "" }
      end

      sig { params(pending_change_id: Integer).returns(T::Hash[Symbol, T.untyped]) }
      def withdraw_pending_change(pending_change_id:)
        change = get_pending_change(id: pending_change_id)
        return { success: false, error_message: "Pending change not found" } unless change

        delete_pending_change_file(pending_change_id)
        { success: true, error_message: "" }
      end

      sig { params(pending_change_id: Integer, actor: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def request_ai_review(pending_change_id:, actor:)
        change = get_pending_change(id: pending_change_id)
        return nil unless change

        ai_review = {
          id: Time.now.to_i,
          pending_change_id: pending_change_id,
          reference_id: change[:reference_id].to_s,
          ai_feedback: "## Dev Mode AI Review\n\n" \
            "**Model:** `#{change[:reference_id]}`\n" \
            "**Change type:** #{change[:target_state]}\n\n" \
            "This is a stub AI review in development mode. " \
            "In production, this calls the Copilot API for a real analysis.\n\n" \
            "### Checklist\n" \
            "- [ ] Verify `referenceID` follows naming conventions\n" \
            "- [ ] Check billing `restrictedTo` plans are correct\n" \
            "- [ ] Confirm endpoint configuration is valid\n",
          prompt_used: "Dev mode stub — no prompt sent",
          requested_by: actor,
          created_at: Time.now.iso8601,
        }

        # Persist the AI review on the pending change
        change[:ai_reviews] = (change[:ai_reviews] || []) + [ai_review]
        change[:updated_at] = Time.now.iso8601
        save_pending_change(change)

        ai_review
      end

      sig { params(reference_id: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def get_yaml_model_history(reference_id:)
        [] # No history in dev mode
      end

      private

      sig { returns(T::Array[String]) }
      def yaml_files
        Dir.glob(File.join(FIXTURES_DIR, "*.yaml")).sort
      end

      sig { params(reference_id: String).returns(String) }
      def file_path(reference_id)
        sanitized = reference_id.gsub(%r{[^a-zA-Z0-9._\-]}, "")
        path = File.expand_path(File.join(FIXTURES_DIR, "#{sanitized}.yaml"))
        unless path.start_with?(FIXTURES_DIR)
          raise ArgumentError, "Invalid reference_id: #{reference_id}"
        end
        path
      end

      sig { params(path: String).returns(T::Hash[String, T.untyped]) }
      def load_yaml(path)
        data = YAML.safe_load(File.read(path))
        data.is_a?(Hash) ? data : {}
      end

      sig { params(path: String, actor: String).void }
      def save_meta(path, actor)
        meta_path = "#{path}.meta.json"
        File.write(meta_path, JSON.generate({ actor: actor }))
      end

      sig { params(path: String).returns(T::Hash[String, T.untyped]) }
      def load_meta(path)
        meta_path = "#{path}.meta.json"
        return {} unless File.exist?(meta_path)

        JSON.parse(File.read(meta_path))
      rescue JSON::ParserError
        {}
      end

      sig { params(data: T::Hash[String, T.untyped], path: String).returns(T::Hash[Symbol, T.untyped]) }
      def build_full_model_hash(data, path)
        billing = data["billing"] || {}
        inline_approval = data["inlineApproval"] || {}
        warning_flags = data["warningMessageFeatureFlags"] || {}

        visible_flags = (data["visibleFeatureFlagChecks"] || []).map do |check|
          conditions = check["conditions"] || {}
          {
            flag_name: check["flagName"].to_s,
            conditions: {
              requires_valid_hmac: conditions["requiresValidHmac"] || false,
              integrations_allow_list: conditions["integrationsAllowList"] || [],
              integration_categories_allow_list: conditions["integrationCategoriesAllowList"] || [],
              sku_allow_list: conditions["skuAllowList"] || [],
            },
          }
        end

        endpoint_flags = (data["endpoints"] || []).map { |ep| ep["featureFlag"] }.compact.uniq

        {
          key: data["policyID"].to_s,
          name: data["name"].to_s,
          description: "A #{data['vendor']} model. Version: #{data['version']}.",
          plans: (billing["restrictedTo"] || []),
          feature_flag: data["featureFlag"].to_s,
          internal: data["isModelPickerEnabled"] == false,
          preview: data["isPreview"] == true,
          documentation_link: data["documentationLink"].to_s,
          documentation_link_text: data["documentationLinkText"].to_s,
          inline_approval_enabled: inline_approval["enabled"] == true,
          policy_pro_feature_flag: data["policyProFeatureFlag"].to_s,
          policy_ga_feature_flag: data["policyGaFeatureFlag"].to_s,
          vendor: data["vendor"].to_s,
          version: data["version"].to_s,
          reference_id: data["referenceID"].to_s,
          inline_approval_terms: inline_approval["terms"].to_s,
          skip_policy_feature_flag: data["skipPolicyFeatureFlag"].to_s,
          retry_feature_flag: data["retryFeatureFlag"].to_s,
          warning_message_high_usage_ff: warning_flags["featureFlagWarningMessageHighUsage"].to_s,
          warning_message_degraded_performance_ff: warning_flags["featureFlagWarningMessageDegradedPerformance"].to_s,
          warning_message_degraded_performance_provider_ff: warning_flags["featureFlagWarningMessageDegradedPerformanceProvider"].to_s,
          visible_feature_flags: visible_flags,
          endpoint_feature_flags: endpoint_flags,
        }
      end

      # --- Pending change file-based persistence helpers ---

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def load_all_pending_changes
        Dir.glob(File.join(PENDING_CHANGES_DIR, "*.json")).filter_map do |path|
          data = JSON.parse(File.read(path))
          symbolize_pending_change(data)
        rescue JSON::ParserError
          nil
        end
      end

      sig { params(change: T::Hash[Symbol, T.untyped]).void }
      def save_pending_change(change)
        path = File.join(PENDING_CHANGES_DIR, "#{change[:id]}.json")
        File.write(path, JSON.pretty_generate(stringify_keys(change)))
      end

      sig { params(id: Integer).void }
      def delete_pending_change_file(id)
        path = File.join(PENDING_CHANGES_DIR, "#{id}.json")
        File.delete(path) if File.exist?(path)
      end

      sig { returns(Integer) }
      def next_pending_change_id
        existing = Dir.glob(File.join(PENDING_CHANGES_DIR, "*.json")).map do |p|
          File.basename(p, ".json").to_i
        end
        (existing.max || 0) + 1
      end

      sig { params(data: T::Hash[String, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
      def symbolize_pending_change(data)
        result = data.transform_keys(&:to_sym)
        result[:id] = result[:id].to_i
        result[:ai_reviews] = (result[:ai_reviews] || []).map { |r| r.is_a?(Hash) ? r.transform_keys(&:to_sym) : r }
        result
      end

      sig { params(hash: T::Hash[Symbol, T.untyped]).returns(T::Hash[String, T.untyped]) }
      def stringify_keys(hash)
        hash.transform_keys(&:to_s).tap do |h|
          h["ai_reviews"] = (h["ai_reviews"] || []).map { |r| r.is_a?(Hash) ? r.transform_keys(&:to_s) : r }
        end
      end
    end
  end
end
