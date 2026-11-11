# typed: true
# frozen_string_literal: true

module DependencyReview
  class RichDiffComponent < ApplicationComponent
    attr_reader :error

    delegate :dependencies, to: :manifest

    def initialize(review_summary:, path:, error: nil)
      @error = error
      @review_summary = review_summary
      @path = path
    end

    def manifest
      @review_summary.manifests.find { |m| m.path == @path }
    end

    def call
      render Primer::Beta::BorderBox.new(border: 0) do |component|
        if error.present?
          component.with_body do
            render Primer::BlankslateComponent.new( # rubocop:disable Primer/DeprecatedComponents
              icon: error.fetch(:icon, "alert"),
              title: error.fetch(:title, "Dependency review cannot load the rich diff."),
              description: error[:body],
            )
          end
        elsif manifest.blank? || dependencies.blank?
          # Currently we can't tell if `manifest.blank?` means that we don't know about the manifest file or if we just
          # didn't detect any changes in the file content. For now, we'll display the same message for both the error
          # case and the case where dependencies didn't change.
          component.with_body do
            render Primer::BlankslateComponent.new( # rubocop:disable Primer/DeprecatedComponents
              title: "No dependencies changed.",
              description: "The changes to this file likely do not affect the dependencies"
            )
          end
        else
          dependencies.each do |dependency|
            component.with_row do
              render DependencyReview::DependencyRowComponent.new(dependency: dependency)
            end
          end
        end

        component.with_footer(bg: :subtle, color: :muted, text: :small, p: 2, classes: "Box--condensed rounded-bottom-2") do
          render DependencyReview::DependencyFooterComponent.new
        end
      end
    end
  end
end
