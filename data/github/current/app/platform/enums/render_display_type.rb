# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class RenderDisplayType < Platform::Enums::Base
      description "The Render display type."

      visibility :internal

      value "DIFF", "A comparison between two blobs.", value: :diff
      value "EDIT", "An edit blob view.", value: :edit
      value "PREVIEW", "A readonly blob preview.", value: :preview
      value "VIEW", "A readonly blob view.", value: :view
    end
  end
end
