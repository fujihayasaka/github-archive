# typed: true
# frozen_string_literal: true

module Discussions
  class LabelSearchContentComponent < ApplicationComponent
    extend T::Sig

    sig { params(repository: T.untyped, parsed_query: T.untyped, org_param: T.nilable(String)).void }
    def initialize(repository:, parsed_query:, org_param: nil)
      @repository = repository
      @parsed_query = parsed_query

      @selected_label_names = Set.new
      @excluded_label_names = Set.new
      @parsed_query.each do |term|
        next unless term.is_a?(Array)

        if term.first == :no && term.second.match?(/\Alabels?\z/i)
          @selected_label_names.add(:missing)
        elsif term.first == :label && !term.third
          @selected_label_names.add(term.second)
        elsif term.first == :label && term.third
          @excluded_label_names.add(term.second)
        end
      end

      @labels = @repository.sorted_labels(cache_label_html: true).partition { |label| checked?(label) }.flatten
      @org_param = org_param
    end

    private

    attr_reader :labels

    sig { returns(T.nilable(String)) }
    attr_reader :org_param

    delegate :discussions_search_path, to: :helpers

    def unlabeled_checked?
      @selected_label_names.include?(:missing)
    end

    def selected?(label)
      @selected_label_names.include?(label.name)
    end

    def excluded?(label)
      @excluded_label_names.include?(label.name)
    end

    def checked?(label)
      selected?(label) || excluded?(label)
    end

    def icon_for_label(label)
      if excluded?(label)
        :"circle-slash"
      else
        :check
      end
    end

    def url_for_no_labels
      append = if unlabeled_checked?
        []
      else
        [[:no, "label"]]
      end

      discussions_search_path(
        replace: { label: nil, no: nil },
        append: append,
        repository: @repository,
        discussions_query: @parsed_query,
        org_param: org_param,
      )
    end

    def url_to_toggle(label)
      append = if selected?(label) || excluded?(label)
        []
      else
        [[:label, label.name]]
      end

      label_search_path(label, append: append)
    end

    def url_to_exclude(label)
      append = if excluded?(label)
        []
      else
        [[:label, label.name, true]]
      end

      label_search_path(label, append: append)
    end

    def label_search_path(label, append:)
      replacement = if selected?(label) || excluded?(label)
        { label: { label.name => nil } }
      else
        {}
      end

      discussions_search_path(
        replace: replacement,
        append: append,
        repository: @repository,
        discussions_query: @parsed_query,
        org_param: org_param,
      )
    end
  end
end
