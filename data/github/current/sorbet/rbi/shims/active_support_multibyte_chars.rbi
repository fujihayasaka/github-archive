# typed: true
# frozen_string_literal: true

# Shim for ActiveSupport::Multibyte::Chars which was removed in Rails 8.2
# (rails/rails#56777). Tapioca 0.17.10 still references it in generated
# ActiveRecord relation RBIs. This shim avoids 2,000+ Sorbet errors until
# Tapioca is updated.
module ActiveSupport
  module Multibyte
    class Chars
    end
  end
end
