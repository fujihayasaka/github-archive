# typed: true
# frozen_string_literal: true

module Discussions
  class IndexSidebarLinksComponent < ApplicationComponent
    def initialize(current_repository:, code_of_conduct_file:, wrap_text: true, show_divider: true)
      @current_repository = current_repository
      @code_of_conduct_file = code_of_conduct_file
      @wrap_text = wrap_text
      @show_divider = show_divider
    end

    attr_reader :current_repository, :code_of_conduct_file, :wrap_text, :show_divider
  end
end
