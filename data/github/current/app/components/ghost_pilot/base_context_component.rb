# typed: true
# frozen_string_literal: true

module GhostPilot
  class BaseContextComponent < ApplicationComponent
    extend T::Sig
    extend T::Helpers

    abstract!

    sig { returns(T.nilable(Symbol)) }
    def feature_flag
      nil
    end

    def before_render
      if feature_flag.present?
        @enabled = user_feature_enabled?(feature_flag)
      else
        @enabled = true
      end
    end

    def render?
      @enabled
    end

    sig { abstract.returns(String) }
    def element_id; end

    private

    def format_array_into_markdown_list(context_array)
      context_array.map { |i| "- #{i}" }.join("\n")
    end
  end
end
