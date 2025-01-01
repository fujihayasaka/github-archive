# typed: true
# frozen_string_literal: true

module Audit
  class Service
    class PreparedData
      extend T::Sig
      include GitHub::Memoizer

      # Boolean fields that need to be cast to strings to prevent mapper_parsing_exceptions in Elasticsearch
      BOOL_FIELDS = [:final, :result]

      attr_reader :input, :output

      # Build and return a hash of Audit Log prepared data from an initial input
      #
      # See initialize method for arguments
      #
      # Returns a Hash of prepared data
      def self.build(input:, discard_timestamp: false)
        new(input: input, discard_timestamp: discard_timestamp).tap(&:build!)
      end

      # Initializer
      #
      # input - Input Hash to expand and prepare for the Audit Log (default: {}).
      # discard_timestamp - Optional, whether the @timestamp field is discarded from the input data
      #                     and set to the current time.
      #
      # Returns a class instance.
      def initialize(input: {}, discard_timestamp: false)
        @input = input
        @discard_timestamp = discard_timestamp
      end

      # Copy and transform the input to Audit Log prepared data. Sets the @output instance variable.
      #
      # Returns a Hash of prepared output.
      def build!
        @data = input.deep_transform_values do |v|
          v.is_a?(ActiveRecord::Base) ? v.as_json(dangerously_allow_all_keys: true) : v.dup
        end.deep_symbolize_keys

        set_document_id!
        set_timestamps!
        set_action_crud!
        set_action_category!
        set_business_fields!
        set_actor_location!
        set_external_identity!
        set_actor_is_bot!
        cast_bool_fields_to_string!
        set_git_hashed_token!

        @output = @data
      end

      # Set a random _document_id if not yet defined on data.
      def set_document_id!
        data[:_document_id] ||= SecureRandom.urlsafe_base64(16)
      end

      # Set @timestamp and created_at fields.
      def set_timestamps!(now = Time.current)
        if data[:timestamp_override].present?
          data[:@timestamp] = Audit.time_to_milliseconds(data[:timestamp_override])
          data.delete(:timestamp_override)
        elsif data[:@timestamp].blank? || @discard_timestamp
          data[:@timestamp] = Audit.time_to_milliseconds(now)
        else
          data[:@timestamp] = Audit.time_to_milliseconds(data[:@timestamp])
        end

        data[:created_at] = Audit.time_to_milliseconds(data[:created_at]) || data[:@timestamp]
        data[:expires_at] = Audit.time_to_milliseconds(data[:expires_at]) if data[:expires_at].present?
      end

      # Set operation_type field.
      def set_action_crud!
        action_crud = Audit::ACTIONS_CRUD[data[:action]]
        data[:operation_type] = action_crud unless action_crud.blank?
      end

      # Set a category for the event, default is OTHER
      def set_action_category!
        category_type = Audit::ActionCategories::ACTIONS[data[:action]]
        data[:category_type] = category_type || Audit::CategoryTypes::TYPES[:OTHER]
      end

      # Set emu_business_id, and other business related fields.
      def set_business_fields!
        if business
          data[:emu_business_id] = business.id if business.enterprise_managed_user_enabled?
          data.merge!(business.event_context) unless data[:business_id]
        end
      end

      # Set actor_location field based on actor_ip.
      def set_actor_location!
        return unless data[:actor_ip].present?

        GitHub.dogstats.distribution_time("audit_service", tags: ["action:ip_lookup"]) do
          location = GitHub::Location.look_up(data[:actor_ip])
          GitHub.audit.normalize_location(location)
          data[:actor_location] = location
        end
      end

      def sso_info(ei_session_owner)
        case ei_session_owner
        when Business
          [ei_session_owner.external_provider_enabled?, ei_session_owner.async_external_provider]
        when Organization
          [ei_session_owner.saml_sso_enabled?, ei_session_owner.async_saml_provider]
        else
          [false, nil]
        end
      end

      def set_external_identity!
        actor = data[:actor_id] ? users_by_id[data[:actor_id]] : nil
        return unless actor

        biz_entity = business
        org_entity = users_by_id[data[:org_id]]
        org_entity = nil unless org_entity&.organization?
        return unless biz_entity || org_entity

        sso_enabled, async_provider = sso_info(biz_entity.external_identity_session_owner) if biz_entity

        unless sso_enabled
          sso_enabled, async_provider = sso_info(org_entity.external_identity_session_owner) if org_entity
        end

        unless sso_enabled && async_provider
          data[:external_identity_username] = "" if data.has_key?(:external_identity_username)
          data[:external_identity_nameid] = "" if data.has_key?(:external_identity_nameid)
          data[:external_id] = "" if data.has_key?(:external_id)
          return
        end

        async_provider.then do |provider|
          if provider
            actor.external_identities.by_provider(provider).each do |ident|
              data[:external_identity_username] = ident.user_name if ident.user_name.present?
              data[:external_identity_nameid] = ident.name_id if ident.name_id.present?
              data[:external_id] = ident.external_id if ident.external_id.present?
              data[:external_id] ||= ident.saml_external_id if ident.saml_external_id.present?
            end
          end
        end.sync
      end

      # Set actor_is_bot field based on actor being a bot or not.
      def set_actor_is_bot!
        actor = data[:actor_id] ? users_by_id[data[:actor_id]] : nil
        return unless actor

        biz_entity = business
        org_entity = users_by_id[data[:org_id]]
        org_entity = nil unless org_entity&.organization?
        return unless biz_entity || org_entity

        data[:actor_is_bot] = actor&.bot?
      end

      # Cast boolean fields to strings to avoid issues with Elasticsearch
      def cast_bool_fields_to_string!
        BOOL_FIELDS.each do |field|
          data[field] = data[field].to_s unless data[field].nil?
        end
      end

      def set_git_hashed_token!
        action = data[:action]
        return unless GitHub.single_business_environment? && action.present? && action.starts_with?("git")
        cred = data[:credential]
        return unless cred.present?
        creds = cred.split(":")
        if creds.length == 3
          data[:hashed_token] = creds[2]
        end
      end

      private

      attr_reader :data

      memoize def users_by_id
        result = {}
        user_ids = [data[:actor_id], data[:user_id], data[:org_id]].compact
        if user_ids.any?
          result = User.where(id: user_ids).index_by(&:id)
        end
        result
      end

      memoize def business
        if GitHub.single_business_environment?
          if data[:org_id]
            Business.from_org_id(data[:org_id])
          else
            GitHub.global_business
          end
        elsif GitHub.multi_tenant_enterprise?
          GitHub::CurrentTenant.get
        else
          if data[:business_id]
            Business.find_by(id: data[:business_id])
          elsif data[:org_id]
            Business.from_org_id(data[:org_id])
          elsif (user_id = data[:user_id] || data[:actor_id])
            users_by_id[user_id].try(:enterprise_managed_business)
          end
        end
      end
    end
  end
end
