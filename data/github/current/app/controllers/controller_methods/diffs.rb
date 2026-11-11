# typed: false
# frozen_string_literal: true

module ControllerMethods
  module Diffs
    def ignore_whitespace?
      %w[1 true].include? params[:w].to_s
    end
  end
end
