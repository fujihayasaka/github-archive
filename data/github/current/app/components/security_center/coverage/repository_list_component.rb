# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Coverage
    class RepositoryListComponent < ApplicationComponent
      extend T::Sig
      include ReactHelper

      TEST_SELECTOR = "security-center-coverage-repository-list"
      ACTIVE_LINK_SELECTOR = "security-center-coverage-repository-list-active-link"
      ARCHIVED_LINK_SELECTOR = "security-center-coverage-repository-list-archived-link"
      ROW_TEST_SELECTOR = "security-center-coverage-repository-list-row"
      ROW_CHECKBOX_TEST_SELECTOR = "security-center-coverage-repository-list-row-checkbox"
      SELECT_ALL_CHECKBOX_TEST_SELECTOR = "security-center-coverage-select-all-rows-checkbox"
      BLANKSLATE_TEST_SELECTOR = "security-center-coverage-repository-list-blankslate"

      renders_many :menus, SelectMenuComponent
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
        const :owner, User
        const :repo_coverages_list, T::Array[RepositoryCoveragesComponent::Data]
        const :risk_url, String
        const :turbo_frame_src, String
      end

      class Data < T::Struct
        const :active_href, String
        const :archived_href, String
        const :is_archived_selected, T::Boolean
        const :is_nonarchived_selected, T::Boolean
        const :list_data, T::Array[ListItemData]
        const :current_page, Integer
        const :multi_repo_enablement_data, T.nilable(::SecurityCenter::Coverage::Enablement::MultiRepoEnablementComponent::Data)
        const :show_enablement, T::Boolean
        const :async_counts_href, String
      end

      sig { returns(String) }; attr_reader :active_href
      sig { returns(String) }; attr_reader :archived_href
      sig { returns(T::Boolean) }; attr_reader :is_archived_selected
      sig { returns(T::Boolean) }; attr_reader :is_nonarchived_selected
      sig { returns(T::Array[ListItemData]) }; attr_reader :list_data
      sig { returns(Integer) }; attr_reader :current_page
      sig { returns(T.nilable(::SecurityCenter::Coverage::Enablement::MultiRepoEnablementComponent::Data)) }; attr_reader :multi_repo_enablement_data
      sig { returns(T::Boolean) }; attr_reader :show_enablement
      sig { returns(String) }; attr_reader :async_counts_href

      sig { params(data: Data).void }
      def initialize(data)
        @active_href = T.let(data.active_href, String)
        @archived_href = T.let(data.archived_href, String)
        @is_archived_selected = T.let(data.is_archived_selected, T::Boolean)
        @is_nonarchived_selected = T.let(data.is_nonarchived_selected, T::Boolean)
        @list_data = T.let(data.list_data, T::Array[ListItemData])
        @current_page = T.let(data.current_page, Integer)
        @multi_repo_enablement_data = T.let(data.multi_repo_enablement_data, T.nilable(::SecurityCenter::Coverage::Enablement::MultiRepoEnablementComponent::Data))
        @show_enablement = T.let(data.show_enablement, T::Boolean)
        @async_counts_href = T.let(data.async_counts_href, String)
      end

      private

      sig { returns(T::Boolean) }
      def render_blankslate?
        list_data.empty? && blankslate?
      end

      sig { returns(T::Boolean) }
      def show_multi_repo_enablement
        @show_enablement && !@multi_repo_enablement_data.nil?
      end

      sig { returns(T::Boolean) }
      def active_highlighted?
        is_nonarchived_selected && !is_archived_selected
      end

      sig { returns(T::Boolean) }
      def archived_highlighted?
        is_archived_selected && !is_nonarchived_selected
      end
    end
  end
end
