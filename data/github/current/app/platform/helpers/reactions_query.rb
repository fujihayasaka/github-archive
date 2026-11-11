# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module ReactionsQuery
      def self.list_reactions(reaction_subject, arguments)
        scope = reaction_subject.reactions.not_spammy.scoped

        if arguments[:order_by]
          scope = scope.order(arguments[:order_by][:field] => arguments[:order_by][:direction])
        else
          scope = scope.order(id: "ASC")
        end

        if arguments[:content]
          scope = scope.where(content: arguments[:content])
        end

        scope
      end
    end
  end
end
