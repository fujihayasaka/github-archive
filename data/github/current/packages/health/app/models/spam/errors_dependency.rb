# typed: true
# frozen_string_literal: true

module Spam::ErrorsDependency

  # Superclass for error sanity.
  class Error < RuntimeError
  end

  # Raised when trying to classify content with a label we don't know.
  class BadLabel < Error
    def initialize(label)
      super "#{label.inspect} isn't a valid label. 'ham' or 'spam' is about it."
    end
  end

  class BadTarget < Error
    def initialize(target)
      super "#{target.class} isn't a class we know how to use for spam training."
    end
  end
end
