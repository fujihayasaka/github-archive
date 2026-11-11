# typed: true
# frozen_string_literal: true

# Checks if a developer is mistakenly trying to render a binary string (usually
# by ERB interpolation or `render inline: str`)
#
# In non-production environments, this module wraps the String methods in
# OutputBuffer to ensure that the strings that we are trying to display are
# valid. For each method that either mutates `self` or produces a new string
# through concatenation or substitution:
# - pass through to `super` if `self.encoding` is already `BINARY` (this is the
#   case if Rails is temporarily `force_encoding` to `BINARY`)
# - raise an exception if the encoding has been changed to
#   `Encoding::ASCII_8BIT` or is invalid
#
# While the vast majority of cases could be covered simply by overriding
# `<<`/`concat`, this module takes a more comprehensive approach just to ensure
# that in the unlikely case a developer is directly manipulating a rendered
# OutputBuffer, we can still catch encoding issues.

# We intentionally want this code not to be loaded in production
unless GitHub::AppEnvironment.production? || ENV["FASTDEV"] # rubocop:disable GitHub/DoNotBranchOnRailsEnv
  module CheckOutputBufferForIncorrectEncoding
    extend T::Helpers
    requires_ancestor { ActionView::OutputBuffer }

    def valid_encoding?
      @raw_buffer.valid_encoding?
    end

    # ActionView::OutputBuffer instance methods that modify the string and need encoding checks
    [:<<, :append=, :safe_expr_append=, :safe_append=, :safe_concat].each do |m|
      define_method(m.to_sym) do |*args, &block|
        T.bind(self, CheckOutputBufferForIncorrectEncoding)

        prev_encoding = self.encoding
        prev_valid = self.valid_encoding?

        result = super(*args, &block)

        # Ignore methods that don't return buffers
        return result unless result.is_a?(self.class)

        # Ignore if Rails has used buffer.force_encoding(Encoding::ASCII_8BIT)
        # or if the encoding is already invalid
        return result if (prev_encoding == Encoding::ASCII_8BIT) || (!prev_valid)

        # If the encoding has been changed to Encoding::ASCII_8BIT or is
        # invalid, alert the developer they are trying to display an invalid
        # encoding
        if self.encoding == Encoding::ASCII_8BIT
          raise NonDisplayableEncodingError.new(:ascii_8bit, self)
        elsif result.encoding == Encoding::ASCII_8BIT
          raise NonDisplayableEncodingError.new(:ascii_8bit, result)
        elsif !self.valid_encoding?
          raise NonDisplayableEncodingError.new(:invalid, self)
        elsif !result.valid_encoding?
          raise NonDisplayableEncodingError.new(:invalid, result)
        end

        result
      end
    end

    class NonDisplayableEncodingError < StandardError
      def initialize(reason, str)
        reason_msg = case reason
        when :ascii_8bit
          "String #{str.inspect} has encoding ASCII_8BIT (BINARY)"
        when :invalid
          "String #{str.inspect} has invalid bytes for its encoding #{str.encoding}"
        end

        super "Could not concatenate to the buffer because #{reason_msg}. See https://thehub.github.com/epd/engineering/products-and-services/dotcom/encodings for guidance on dealing with encodings."
      end
    end
  end

  ActionView::OutputBuffer.send(:prepend, CheckOutputBufferForIncorrectEncoding)
end
