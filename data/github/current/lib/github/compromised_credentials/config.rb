# typed: true
# frozen_string_literal: true

module GitHub
  module CompromisedCredentials
    module Config
      # Feature flags for controlling compromised credentials data sources

      # Check if CompromisedCreds should be used
      def self.use_compromised_creds?
        FeatureFlag.vexi.enabled?(:use_compromised_creds, default: false)
      end

      # Check if Qintel should be used
      def self.use_qintel?
        # Qintel is used by default unless explicitly disabled
        return false if FeatureFlag.vexi.enabled?(:disable_qintel, default: false)

        # If we're exclusively using CompromisedCreds, don't use Qintel
        return false if FeatureFlag.vexi.enabled?(:use_compromised_creds_exclusively, default: false) && use_compromised_creds?

        true
      end

      def self.compromised_creds_processing_enabled?
        FeatureFlag.vexi.enabled?(:process_compromised_creds_events, default: false)
      end

      def self.active_datasources
        sources = []

        sources << "compromised_creds" if use_compromised_creds?
        sources << "qintel" if use_qintel?

        sources
      end

      def self.should_process_qintel?
        use_qintel?
      end

      def self.should_process_compromised_creds?
        use_compromised_creds? && compromised_creds_processing_enabled?
      end

      def self.using_both_sources?
        use_compromised_creds? && use_qintel?
      end

      def self.using_only_compromised_creds?
        use_compromised_creds? && !use_qintel?
      end

      def self.using_only_qintel?
        !use_compromised_creds? && use_qintel?
      end

      def self.no_datasources_active?
        active_datasources.empty?
      end
    end
  end
end
