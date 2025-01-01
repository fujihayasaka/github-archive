# typed: strict
# frozen_string_literal: true

require "fm_lite_process_helper"

module FeatureFlag
  module Adapters
    class FeatureManagementLiteAdapter < VexiManagement::Adapters::FeatureManagementLiteAdapter
      include TestAdapter

      sig { params(data_client: GitHub::FaradayClient::Internal, management_client: GitHub::FaradayClient::Internal, default_enabled: T::Boolean, exception_feature_flags: T::Array[String]).void }
      def initialize(data_client, management_client, default_enabled: false, exception_feature_flags: [])
        if GitHub.feature_management_feature_flag_hub_url.nil?
          raise FeatureManagement::FeatureFlagHubClientError.new(:environment_error, "Feature Flag Hub url cannot be nil")
        end

        @default_enabled = T.let(default_enabled, T::Boolean)
        @exception_feature_flags = T.let(exception_feature_flags, T::Array[String])

        @data_adapter = T.let(Vexi::Adapters::MonolithOptimizedFeatureFlagDataAdapter.new_from_connection(data_client), Vexi::Adapters::MonolithOptimizedFeatureFlagDataAdapter)

        features_client = T.let(FFMV3::FeatureFlagsClient.new(management_client), FFMV3::FeatureFlagsClient)
        segments_client = T.let(FFMV3::SegmentMembersClient.new(management_client), FFMV3::SegmentMembersClient)
        super(features_client, segments_client)

        FeatureManagementLiteProcessHelper.ensure_fm_lite_ready
      end

      # Vexi::Adapter

      sig { override.returns(String) }
      def adapter_name
        "fm_lite"
      end

      sig { override.params(names: T::Array[String]).returns(T::Array[Vexi::GetFeatureFlagResponse]) }
      def get_feature_flags(names)
        flag_responses = T.let(@data_adapter.get_feature_flags(names), T::Array[Vexi::GetFeatureFlagResponse])
        flag_responses = flag_responses.select { |flag_response| flag_response.feature_flag }

        missing_flag_names = names - flag_responses.map(&:name)
        missing_flag_names.each do |name|
          is_exception = @exception_feature_flags.include?(name)
          enabled = is_exception ? !@default_enabled : @default_enabled
          flag_responses << Vexi::GetFeatureFlagResponse.new(
            name: name,
            feature_flag: Vexi::FeatureFlag.new(name, boolean_gate: enabled)
          )
        end

        flag_responses
      end

      sig { override.params(names: T::Array[String]).returns(T::Array[Vexi::GetSegmentResponse]) }
      def get_segments(names)
        []
      end

      # FeatureFlag::Adapters::TestAdapter

      sig { override.void }
      def reset
        delete("*")
      end
    end
  end
end
