# typed: true
# frozen_string_literal: true

module Stafftools
  module RepositoryViews
    class LanguagesView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

      attr_reader :repository
      attr_reader :params

      def page_title
        "#{repository.name_with_owner} - Languages"
      end

      def detectable_language_types
        Linguist::BlobHelper::DETECTABLE_TYPES
      end

      def breakdown
        @breakdown ||= repository.language_breakdown.sort do |a, b|
          b[1] <=> a[1]
        end
      end

      def has_breakdown?
        breakdown.any?
      end

      def show_file_breakdown?
        params.delete(:breakdown) == "1"
      end

      def file_breakdown
        @file_breakdown ||= repository.files_by_language
      rescue GitHub::DGit::UnroutedError
        {}
      end
    end
  end
end
