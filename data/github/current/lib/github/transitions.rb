# typed: strict
# frozen_string_literal: true

module GitHub
  module Transitions
    autoload :Base, "github/transitions/base"
    autoload :EncryptColumnWithCurrentKey, "github/transitions/encrypt_column_with_current_key"
    autoload :Arguments, "github/transitions/arguments"
    autoload :Iterators, "github/transitions/iterators"
  end
end
