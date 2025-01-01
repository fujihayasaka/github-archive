# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Risk
    # This heavily mimics the same on the Coverage page. Once the features have stabilized and shipped, investigate
    # how we might consolidate the component through the use of slots or other extension mechanisms.
    class RepositoryListComponent < ApplicationComponent

      # alias these so we don't have to move them somewhere more global
      # TODO move these somewhere more global :)
      RepositoryMetadataComponent = ::SecurityCenter::Coverage::RepositoryMetadataComponent
      ActionMenuComponent = ::SecurityCenter::ActionMenuComponent

      TEST_SELECTOR = "security-center-risk-repository-list"
      ACTIVE_LINK_SELECTOR = "security-center-risk-repository-list-active-link"
      ARCHIVED_LINK_SELECTOR = "security-center-risk-repository-list-archived-link"
      ROW_TEST_SELECTOR = "security-center-risk-repository-list-row"
      BLANKSLATE_TEST_SELECTOR = "security-center-risk-repository-list-blankslate"

      renders_many :action_menus, ActionMenuComponent
      renders_one :blankslate, -> (icon:, heading:, &block) do
        Primer::Beta::Blankslate.new(
          spacious: true,
          classes: ["blankslate-large"],
          test_selector: BLANKSLATE_TEST_SELECTOR,
        ).tap do |c|
          c.with_visual_icon(icon: icon)
          c.with_heading(tag: :h3) { heading }
          c.with_description(&block)
        end
      end

      class ListItemData < T::Struct
        const :repo_metadata, RepositoryMetadataComponent::Data
        const :repo_alert_count_map, T::Hash[Symbol, RepositoryAlertCountComponent::Data]

        def initialize(repo_metadata:, repo_alert_count_map:)
          super

          if (repo_alert_count_map.keys - RepositorySecurityCenterStatus.primary_feature_types).size > 0 ||
            repo_alert_count_map.values.any? { |data| !data.is_a?(RepositoryAlertCountComponent::Data) }
            raise TypeError, "repo_alert_count_map must be a Hash of feature types to #{RepositoryAlertCountComponent::Data}"
          end
        end
      end

      class Data < T::Struct
        const :active_href, String
        const :archived_href, String
        const :is_archived_selected, T::Boolean
        const :is_nonarchived_selected, T::Boolean
        const :list_data, T::Array[ListItemData]
        const :current_page, Integer
        const :async_counts_href, String
      end

      sig { returns(String) }; attr_reader :active_href
      sig { returns(String) }; attr_reader :archived_href
      sig { returns(T::Boolean) }; attr_reader :is_archived_selected
      sig { returns(T::Boolean) }; attr_reader :is_nonarchived_selected
      sig { returns(T::Array[ListItemData]) }; attr_reader :list_data
      sig { returns(Integer) }; attr_reader :current_page
      sig { returns(String) }; attr_reader :async_counts_href

      sig { params(data: Data).void }
      def initialize(data)
        @active_href = T.let(data.active_href, String)
        @archived_href = T.let(data.archived_href, String)
        @is_archived_selected = T.let(data.is_archived_selected, T::Boolean)
        @is_nonarchived_selected = T.let(data.is_nonarchived_selected, T::Boolean)
        @list_data = T.let(data.list_data, T::Array[ListItemData])
        @current_page = T.let(data.current_page, Integer)
        @async_counts_href = T.let(data.async_counts_href, String)
      end

      private

      sig { returns(T::Boolean) }
      def render_blankslate?
        list_data.empty? && blankslate?
      end

      sig { returns(T::Boolean) }
      def active_highlighted?
        is_nonarchived_selected && !is_archived_selected
      end

      sig { returns(T::Boolean) }
      def archived_highlighted?
        is_archived_selected && !is_nonarchived_selected
      end

      sig { returns(T::Array[Symbol]) }
      def features
        keys = list_data.flat_map { |list_item_data| list_item_data.repo_alert_count_map.keys }.uniq
        primary_feature_keys = (RepositorySecurityCenterStatus.primary_feature_types & keys)
        primary_feature_keys + (keys - primary_feature_keys) # order by primary_feature_types first then any unrecognized features
      end

      # Primer grids use a 12 column number system: https://primer.style/view-components/system-arguments#grid
      # This method calculates the column span to use for the metadata section.
      sig { returns(Integer) }
      def metadata_col
        12 - alert_counts_col
      end

      # Primer grids use a 12 column number system: https://primer.style/view-components/system-arguments#grid
      # This method calculates the column span to use for the alert counts section.
      sig { returns(Integer) }
      def alert_counts_col
        max_feature_columns = RepositorySecurityCenterStatus.primary_feature_types.size
        feature_columns = [features.size, max_feature_columns].min
        [7, feature_columns * 3].min
      end
    end
  end
end
