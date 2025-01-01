# typed: true
# frozen_string_literal: true

module Comments
  class CommentActorComponent < ApplicationComponent
    include BotHelper

    attr_reader :actor, :show_full_name, :link_class

    def initialize(actor:, show_full_name: false, link_class: "")
      @actor = actor
      @show_full_name = show_full_name
      @link_class = link_class
    end

    def link_options
      {
        class: "author Link--primary text-bold css-overflow-wrap-anywhere #{link_class}",
        show_full_name: show_full_name,
      }
    end
  end
end
