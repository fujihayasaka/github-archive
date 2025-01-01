# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Coverage
    class RepositoryCoveragesComponent < ApplicationComponent

      TEST_SELECTOR = "security-center-coverage-repository-coverage"
      COVERAGES_TEST_SELECTOR = "security-center-coverage-repository-coverage-coverages"

      class Data < T::Struct
        const :feature, String
        const :coverages, T::Array[String]
        const :no_coverages_reason, String
        const :feature_statuses, T::Hash[Symbol, String]
        const :keyword_init, T::Boolean, default: true
      end

      sig { params(repo_id: Integer, data: Data, owner: User).void }
      def initialize(repo_id, data, owner)
        @repo_id = repo_id
        @data = data
        @feature = T.let(data.feature, String)
        @owner = owner
      end

      sig { returns(String) }
      def coverages_text
        return "Updating..." if enablement_in_progress_for_feature?
        @data.coverages.empty? ? @data.no_coverages_reason : @data.coverages.join(", ").humanize
      end

      sig { returns(Symbol) }
      def text_color
        @data.coverages.empty? && !enablement_in_progress_for_feature? ? :muted : :default
      end

      sig { returns(T.nilable(T::Boolean)) }
      memoize def enablement_in_progress_for_feature?
        return false unless enablement_updates.present?

        case @feature
        when "Dependabot"
          %w[dependency_graph vulnerability_alerts vulnerability_updates].each do |feature|
            return true if enablement_updates.any? { |update| update.include? feature }
          end
          false
        when "Secret scanning"
          enablement_updates.any? { |update| update.include? "token_scanning" }
        end
      end

      sig { returns(T::Array[String]) }
      memoize def enablement_updates
        return [] if flash[:error]
        return [] unless flash["enablement_updated"]

        flash["enablement_updated"][@repo_id.to_s] || []
      end

      sig { returns(T::Boolean) }
      def async_load?
        return false unless @feature == "Code scanning"
        return false unless @owner.organization?
        !@data.coverages.include?("Default setup")
      end
    end
  end
end
