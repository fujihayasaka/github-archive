# typed: true
# frozen_string_literal: true
require "securerandom"

module TrackingBlocks
  class TasklistBlockTitleComponent < ApplicationComponent
    extend T::Sig
    include GitHub::Goomba::Reference::Helpers

    attr_reader :title, :safe_title, :title_tag, :readonly, :is_completed, :is_precache, :parent_issue

    alias readonly? readonly
    alias is_completed? is_completed
    alias is_precache? is_precache

    def initialize(
      title: nil,
      safe_title: nil,
      title_tag: "h3",
      readonly: false,
      is_completed: false,
      is_precache: false,
      parent_issue: nil
    )
      @title = title
      @safe_title = safe_title
      @title_tag = title_tag

      @readonly = readonly
      @is_completed = is_completed
      @is_precache = is_precache

      @parent_issue = parent_issue
    end
  end
end
