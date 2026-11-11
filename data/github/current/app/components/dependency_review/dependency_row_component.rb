# typed: true
# frozen_string_literal: true

module DependencyReview
  class DependencyRowComponent < ApplicationComponent
    attr_accessor :dependency

    delegate :is_vulnerable?, :change_type, to: :dependency

    def initialize(dependency:)
      @dependency = dependency
    end

    def octicon_kargs
      case @dependency.change_type
      when :added then { icon: "diff-added", color: :success, mr: 1 }
      when :removed then { icon: "diff-removed", color: :danger, mr: 1 }
      when :updated then { icon: "diff-modified", color: :attention, mr: 1 }
      end
    end
  end
end
