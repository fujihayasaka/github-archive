# typed: false
# frozen_string_literal: true

# Methods in this class overrides the automatic generated ones
# in sorbet/rbi/dsl/copilot/chat_attachment.rbi within CommonRelationMethods module.
# Its is intentionally typed: false as adding new argument to the method generates
# a sorbet error.
module Copilot
  class ChatAttachment
    module CommonRelationMethods
      # This can be removed once tapioca updates the rbi files for ActiveRecord
      sig do
        params(
          of: Integer,
          start: T.untyped,
          finish: T.untyped,
          load: T.untyped,
          error_on_ignore: T.untyped,
          order: Symbol,
          use_ranges: T.untyped,
          cursor: T.untyped,
          block: T.nilable(T.proc.params(object: PrivateRelation).void)
        ).returns(T.nilable(::ActiveRecord::Batches::BatchEnumerator))
      end
      def in_batches(of: 1000, start: nil, finish: nil, load: false, error_on_ignore: nil, order: :asc, use_ranges: nil, cursor: nil, &block); end
    end
  end
end
