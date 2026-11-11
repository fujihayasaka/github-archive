# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  # Shared controller module for Settings SDK pages.
  # Provides standard actions for settings CRUD and a consolidated metadata endpoint
  # that handles targeting search, property metadata, target counting, and test evaluation.
  module SettingsControllerMethods
    extend T::Helpers

    requires_ancestor { ApplicationController }

    VIEW_ACTIONS = [:settings_metadata]
    EDIT_ACTIONS = [:settings_update]

    abstract!

    # --- Abstract methods implementers must define ---

    sig { abstract.returns(SettingsCoreV2::DomainAccessorBase) }
    protected def settings_domain; end

    sig { abstract.returns(T.untyped) }
    protected def settings_resource; end

    sig { abstract.returns(T::Array[String]) }
    protected def setting_names; end

    sig { abstract.returns(T::Boolean) }
    protected def can_write?; end

    # --- Consolidated metadata endpoint ---

    # POST /settings/metadata
    # Body: { type: "search" | "resolve" | "properties" | "target_count" | "test", ... }
    #
    # Dispatches to the appropriate handler based on `type`:
    #   - search:       { type: "search", attribute: "...", q: "query" }
    #   - resolve:      { type: "resolve", attribute: "...", ids: [...] }
    #   - properties:   { type: "properties", attribute: "..." }
    #   - target_count: { type: "target_count", settingName: "...", conditionExpression: {...} }
    #   - test:         { type: "test", targetId: 123, settingName: "...", unsavedSetting?: {...} }
    sig { void }
    def settings_metadata
      body = begin
        JSON.parse(request.body.read)
      rescue JSON::ParserError
        return render json: { error: "Malformed JSON" }, status: :bad_request
      end

      case body["type"]
      when "search"
        handle_search(body)
      when "resolve"
        handle_resolve(body)
      when "properties"
        handle_properties(body)
      when "target_count"
        handle_target_count(body)
      when "test"
        handle_test(body)
      else
        render json: { error: "Unknown metadata type: #{body['type']}" }, status: :bad_request
      end
    end

    # --- Settings update ---

    sig { void }
    def settings_update
      return render json: { error: "Forbidden" }, status: :forbidden unless can_write?

      body = begin
        JSON.parse(request.body.read)
      rescue JSON::ParserError
        return render json: { error: "Malformed JSON" }, status: :bad_request
      end

      settings_array = body["settings"]
      return render json: { error: "Invalid settings format" }, status: :bad_request unless settings_array.is_a?(Array)

      memory_settings = settings_array.filter_map do |setting_json|
        next unless setting_json.is_a?(Hash) && setting_json["name"].present?

        MemorySetting.from_hash(setting_json, settings_resource)
      end

      if memory_settings.empty?
        return render json: { error: "No valid settings provided" }, status: :unprocessable_entity
      end

      unless settings_domain.update_settings(settings_resource, memory_settings, actor: current_user)
        return render json: { error: "Failed to update settings" }, status: :unprocessable_entity
      end

      setting_names_to_reload = memory_settings.map(&:name).uniq
      reloaded = settings_domain.load_settings({ settings_resource => setting_names_to_reload })

      render json: {
        settings: reloaded.map(&:serialize),
      }
    end

    class SettingsPayload < ReactPayload::Base
      extend T::Helpers

      abstract!

      sig do
        params(
          definitions: T::Array[T::Hash[String, T.untyped]],
          settings: T::Array[T::Hash[String, T.untyped]],
          resource: T::Hash[String, T.untyped],
          can_write: T::Boolean,
          groups: T.nilable(T::Array[SettingsCoreV2::RuleGroup]),
        ).void
      end
      def initialize(definitions:, settings:, resource:, can_write:, groups: nil)
        @definitions = definitions
        @settings = settings
        @resource = resource
        @can_write = can_write
        @groups = groups
      end

      sig { override.returns(T::Hash[String, T.untyped]) }
      def payload
        payload = {
          definitions: @definitions,
          settings: @settings,
          resource: @resource,
          canWrite: @can_write,
        }
        if @groups
          payload[:groups] = @groups.map(&:serialize)
        end

        payload
      end
    end

    protected

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def load_settings_payload
      resource = settings_resource
      definitions = settings_domain.setting_definitions(setting_names)
      settings = settings_domain.load_settings({ resource => setting_names })
      resource_def = definitions.flat_map(&:resource_definitions).find { |rd| rd.is_resource?(resource) }

      payload = {
        definitions: definitions.map { |d| d.ui_payload(domain: settings_domain, resource: resource) },
        settings: settings.map(&:serialize),
        resource: resource_def&.ui_payload(resource),
        canWrite: can_write?,
      }

      payload
    end

    private

    sig { params(body: T::Hash[String, T.untyped]).void }
    def handle_search(body)
      attribute = body["attribute"]
      query = body["q"].to_s.strip
      limit = (body["limit"] || 20).to_i.clamp(1, 50)
      setting_name = body["settingName"] || setting_names.first
      definition = settings_domain.definition_by_name(setting_name)
      return render json: { error: "Unknown setting: #{setting_name}" }, status: :bad_request unless definition

      matcher = find_matcher(setting_name, attribute)
      return render json: { error: "Unknown attribute: #{attribute}" }, status: :bad_request unless matcher

      results = matcher.search(settings_resource, query, limit:).filter_map do |result|
        definition.resource_definitions.find { |rd| rd.is_resource?(result) }&.ui_payload(result)
      end
      render json: results
    end

    sig { params(body: T::Hash[String, T.untyped]).void }
    def handle_resolve(body)
      attribute = body["attribute"]
      ids = Array(body["ids"]).map(&:to_s).reject(&:blank?).uniq
      setting_name = body["settingName"] || setting_names.first
      definition = settings_domain.definition_by_name(setting_name)
      return render json: { error: "Unknown setting: #{setting_name}" }, status: :bad_request unless definition

      matcher = find_matcher(setting_name, attribute)
      return render json: { error: "Unknown attribute: #{attribute}" }, status: :bad_request unless matcher

      results = matcher.resolve(settings_resource, ids).filter_map do |result|
        definition.resource_definitions.find { |rd| rd.is_resource?(result) }&.ui_payload(result)
      end
      render json: results
    end

    sig { params(body: T::Hash[String, T.untyped]).void }
    def handle_properties(body)
      attribute = body["attribute"]
      setting_name = body["settingName"] || setting_names.first

      matcher = find_matcher(setting_name, attribute)
      return render json: { error: "Unknown attribute: #{attribute}" }, status: :bad_request unless matcher

      props = matcher.metadata(settings_resource)
      render json: { properties: props || [] }
    end

    sig { params(body: T::Hash[String, T.untyped]).void }
    def handle_target_count(body)
      setting_name = body["settingName"] || setting_names.first
      definition = settings_domain.definition_by_name(setting_name)
      return render json: { error: "Unknown setting: #{setting_name}" }, status: :bad_request unless definition
      matchers = definition.resource_definitions.map(&:matchers).flatten
      conditions = flatten_conditions(body["conditionExpression"] || body)

      counts = conditions.filter_map do |cond|
        attr = cond["targetableAttribute"]
        value = cond["value"]
        operation = IConditionExpression::Operation.try_deserialize(cond["operation"] || "eq")
        next if value.blank? || attr.blank? || operation.nil?

        attribute_name, sub_type = IConditionExpression.split_attribute(attr)
        matcher = matchers.find { |m| m.attribute == attribute_name }
        next unless matcher

        matcher.count_matches(settings_resource, operation, value, sub_type)
      end

      result = if counts.empty?
        { count: 0, total: 0 }
      else
        { count: counts.map { |c| c[:count] }.min || 0, total: counts.first&.dig(:total) || 0 }
      end

      render json: result
    end

    sig { params(body: T::Hash[String, T.untyped]).void }
    def handle_test(body)
      target_type = body["targetType"]
      target_id = body["targetId"]
      setting_name = body["settingName"] || setting_names.first
      return render json: { error: "targetId is required" }, status: :unprocessable_entity unless target_id
      definition = settings_domain.definition_by_name(setting_name)
      return render json: { error: "Unknown setting: #{setting_name}" }, status: :bad_request unless definition
      resource_def = definition.resource_definitions.find { |rd| rd.resource_type.serialize == target_type }
      return render json: { error: "Setting #{setting_name} does not apply to target type #{target_type}" }, status: :bad_request unless resource_def

      target = resource_def.from_id(target_id)
      return render json: { error: "Target not found" }, status: :not_found unless target

      if body["unsavedSetting"].present?
        proposed = MemorySetting.from_hash(body["unsavedSetting"], settings_resource)
        settings_domain.with_settings_override([proposed]) do
          render_test_result(target, setting_name, unsaved: true)
        end
      else
        render_test_result(target, setting_name)
      end
    end

    sig { params(target: T.untyped, setting_name: String, unsaved: T::Boolean).void }
    def render_test_result(target, setting_name, unsaved: false)
      definition = settings_domain.definition_by_name(setting_name)
      return render json: { error: "Unknown setting: #{setting_name}" }, status: :bad_request unless definition

      effective_value = settings_domain.effective_value(target, setting_name, definition.class)
      source_value = settings_domain.effective_value(settings_resource, setting_name, definition.class)

      resource_def = definition.resource_definitions.find { |rd| rd.is_resource?(target) }
      return render json: { error: "Target type #{target.class.name} is not supported for setting #{setting_name}" }, status: :bad_request unless resource_def

      result = {
        resource: resource_def.ui_payload(target),
        settingName: setting_name,
        sourceValue: source_value.respond_to?(:serialize) ? source_value.serialize : source_value,
        effectiveValue: effective_value.respond_to?(:serialize) ? effective_value.serialize : effective_value,
        isOverridden: effective_value != source_value,
      }
      result[:unsaved] = true if unsaved

      render json: result
    end

    sig { params(setting_name: String, attribute: T.nilable(String)).returns(T.nilable(SettingsCoreV2::ConditionMatcher)) }
    def find_matcher(setting_name, attribute)
      return nil unless attribute
      definition = settings_domain.definition_by_name(setting_name)
      return nil unless definition
      definition.resource_definitions.each do |rd|
        rd.matchers.each do |matcher|
          return matcher if matcher.attribute == attribute
        end
      end
      nil
    end

    sig { params(expr: T::Hash[String, T.untyped]).returns(T::Array[T::Hash[String, T.untyped]]) }
    def flatten_conditions(expr)
      if expr["operation"] == "and" && expr["childConditionExpressions"].is_a?(Array)
        expr["childConditionExpressions"]
      else
        [expr]
      end
    end
  end
end
