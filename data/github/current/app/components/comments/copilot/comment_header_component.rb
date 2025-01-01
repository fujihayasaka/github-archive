# typed: true
# frozen_string_literal: true

module Comments
  module Copilot
    class CommentHeaderComponent < Comments::CommentHeaderComponent
      def bot
        comment&.user
      end
    end
  end
end
