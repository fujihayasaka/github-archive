# typed: strict
# frozen_string_literal: true
module Copilot
  module Instrumentation
    module Helpers
      extend T::Sig

      SETTINGS_TO_HIDE_FROM_AUDIT_LOG = T.let([:custom_models_setting, :private_docs_setting, :usage_telemetry_api_setting], T::Array[Symbol])

      sig do
        params(
          event: String,
          payload: T::Hash[Symbol, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
          staff: T::Boolean,
        ).returns(GitHub::Result)
      end
      def instrument(event, payload = {}, staff = false)
        GitHub.dogstats.increment(event)

        # send event to audit log
        audit_payload = build_audit_payload(payload, staff)
        GitHub.instrument(event, audit_payload)

        send_to_hydro(event, payload)
      end

      sig do
        params(
          event: String,
          payload: T::Hash[Symbol, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
          staff: T::Boolean,
        ).returns(GitHub::Result)
      end
      def send_to_hydro(event, payload = {}, staff = false)
        # send event to Hydro
        GitHub::Result.new { GlobalInstrumenter.instrument(event, payload) }
      end

      sig { params(utm_query_params: T::Hash[Symbol, String]).returns(T::Hash[Symbol, String]) }
      def utm_parameters(utm_query_params)
        {
          utm_source: utm_query_params.fetch(:utm_source, ""),
          utm_medium: utm_query_params.fetch(:utm_medium, ""),
          utm_campaign: utm_query_params.fetch(:utm_campaign, ""),
          utm_term: utm_query_params.fetch(:utm_term, ""),
          utm_content: utm_query_params.fetch(:utm_content, ""),
        }
      end

      # rubocop:disable Sorbet/ForbidTUntyped
      sig { params(payload: T::Hash[Symbol, T.untyped], staff: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
      def build_audit_payload(payload, staff)
        audit_payload = payload.dup

        audit_payload[:business]    ||= audit_payload[:business] if audit_payload[:business].present?
        audit_payload[:business_id] ||= audit_payload[:business].id if audit_payload[:business].present?
        audit_payload[:org_id]      ||= audit_payload[:organization_id] if audit_payload[:organization_id].present?
        audit_payload[:org]         ||= audit_payload[:organization] if audit_payload[:organization].present?
        audit_payload[:repo_id]     ||= audit_payload[:repository_id] if audit_payload[:repository_id].present?
        audit_payload[:repo]        ||= audit_payload[:repository] if audit_payload[:repository].present?
        audit_payload[:user_id]     ||= audit_payload[:user].id if audit_payload[:user].present?
        audit_payload[:user]        ||= audit_payload[:copilot_user].user_object if audit_payload[:copilot_user].present?

        # we're also sending owner as a thing.  that makes things even more confusing, but we gotta check it
        if audit_payload[:owner].present?
          if audit_payload[:owner].is_a?(::Business)
            audit_payload[:business_id] = audit_payload[:owner].id
            audit_payload[:business]    = audit_payload[:owner]
          else
            audit_payload[:org_id] = audit_payload[:owner].id
            audit_payload[:org]    = audit_payload[:owner]
          end
        end

        if payload[:actor].present?
          if staff
            audit_payload.merge!(GitHub.guarded_audit_log_staff_actor_entry(payload[:actor]))
          else
            audit_payload[:actor] = payload[:actor].display_login if payload[:actor].respond_to?(:display_login)
            audit_payload[:actor_id] = payload[:actor].id
          end
        else
          # if :actor is nil we want to make sure actor_id is also nil
          audit_payload[:actor_id] = nil
        end

        if payload[:old_value].present?
          audit_payload[:previous_value] = payload[:old_value]
          audit_payload.delete(:old_value)
        end

        if payload[:copilot_for_business_details].present?
          audit_payload[:details] = { payload[:copilot_for_business_details][:key] => payload[:copilot_for_business_details][:value] }
        end

        if payload[:assignment].present?
          assignment = payload[:assignment]

          audit_payload[:seat_assignment] = assignment.audit_log_payload
          if assignment.assignable.is_a?(::User)
            audit_payload[:user] = assignment.assignable
            audit_payload[:user_id] = assignment.assignable_id
          elsif assignment.assignable.is_a?(::OrganizationInvitation)
            if assignment.assignable.email.present?
              audit_payload[:seat_assignment][:assignee] = assignment.assignable.email
            end
          end

          # We want to respect if the actor is explicitly set to nil, otherwise we take the assigning user
          if !payload.include?(:actor)
            audit_payload[:actor] = assignment&.assigning_user&.display_login
            audit_payload[:actor_id] = assignment&.assigning_user&.id
          end
        end

        if payload[:seat].present?
          audit_payload[:seat] = payload[:seat].audit_log_payload
          audit_payload[:seat_assignment] = payload[:seat]&.seat_assignment&.audit_log_payload
          audit_payload[:user] = payload[:seat].assigned_user
          audit_payload[:user_id] = payload[:seat].assigned_user.id
        end

        if payload[:old_settings].present?
          audit_payload[:old_settings] = audit_log_settings_hash(payload[:old_settings])
        end

        if payload[:new_settings].present?
          audit_payload[:new_settings] = audit_log_settings_hash(payload[:new_settings])
        end

        if payload[:blocking_reason].present?
          audit_payload[:reason] = payload[:blocking_reason]
        elsif payload[:reason].present?
          audit_payload[:reason] = payload[:reason]
        end

        audit_payload
      end

      # ugly method to make a pretty settings hash for the user-facing audit log
      sig { params(settings_hash: T::Hash[Symbol, String]).returns(T::Hash[String, String]) }
      def audit_log_settings_hash(settings_hash)
        new_hash = {}

        settings_hash.each do |key, value|
          next if SETTINGS_TO_HIDE_FROM_AUDIT_LOG.include?(key)

          new_key = key.to_s.delete_suffix("_setting")
          value = value.to_s.downcase

          new_key.gsub!("copilot_enabled", "copilot")

          # TODO: we can remove this logic when snippy_setting is renamed to public_code_suggestions in copilot_*_settings
          if new_key.include?("snippy")
            new_key.gsub!("snippy", "public_code_suggestions")
            value = case value
            when "snippy_enabled"
              "blocked"
            when "snippy_disabled"
              "allowed"
            else
              value.delete_prefix!("snippy_")
            end
          end

          new_hash[new_key] = T.must(value).gsub("#{new_key}_", "")
        end

        new_hash
      end
    end
  end
end
