# rubocop:disable Style/FrozenStringLiteralComment
require "charlock_holmes"
require "charlock_holmes/string"

module GitRPC
  # Set of helper methods for dealing with encodings in the app.
  # It would be good of us to reuse this across all of our apps.
  #
  # It will always work toward giving back UTF-8 content
  module Encoding
    extend self

    BINARY     = "ASCII-8BIT"
    UTF8       = "UTF-8"
    DETECTABLE_LEN = 30
    VALID_UTF8 = {
      :encoding      => UTF8,
      :ruby_encoding => UTF8,
      :confidence    => 100,
    }

    # Try to guess the encoding
    #
    # content - a string
    #
    # Returns a Hash, with :encoding, :ruby_encoding, :confidence, :type and
    #         optionally :language. This will return nil if an error occurred during
    #         detection or no valid encoding could be found.
    #         The hash keys are defined as follows:
    #           :encoding      - The name of the encoding ICU detected
    #           :ruby_encoding - The name of the Ruby encoding compatible with :encoding.
    #                            In Ruby 1.8 this will be the same value as :encoding.
    #           :confidence    - Detection confidence value of 0-100
    #           :type          - Will be either :text or :binary
    #           :language      - May or may not exist, but will be the detected spoken
    #                            language of the text.
    def guess(content)
      return if content.nil?

      if valid_utf8?(content)
        detected = VALID_UTF8
      else
        GitRPC.instrument :charlock_detect, :bytesize => content.bytesize do |payload|
          detected = encoding_detector.detect(content)

          if detected && detected[:encoding]
            payload[:encoding] = detected[:encoding]
          end

          detected
        end
      end

      detected
    end
    alias guess_encoding guess

    # Detect and tag a string's encoding.
    # This method will first attempt a detection and upon success
    # will tag the string with a Ruby-compatible encoding
    # name. Then finally returns the detected encoding name from ICU.
    #
    # text - A String to perform encoding detection upon
    #
    # Returns the detected encoding name or nil.
    # If nil is returned the content was detected to be binary or detection
    # failed - in which case our best option is to assume binary anyway.
    def guess_and_tag(text)
      return if text.nil?

      detection = guess(text)

      if detection && detection[:ruby_encoding] && detection[:ruby_encoding] != "binary"
        text.force_encoding(detection[:ruby_encoding])
        detection[:encoding]
      else
        text.force_encoding("binary")
        nil
      end
    end

    # Lookup a Ruby-compatible encoding based on the encoding
    # parameter and tag the string with that encoding. If encoding
    # is nil, the string is tagged  as ASCII-8BIT. This is mostly
    # for use by GitRPC::Client calls that need to re-tag strings
    # that have lost their encoding metadata over the wire.
    #
    # Returns nothing.
    def tag_compatible(text, encoding)
      return if text.nil?

      if encoding.nil?
        text.force_encoding(BINARY)
      elsif ruby_encoding = lookup(encoding)
        text.force_encoding(ruby_encoding)
      else
        text.force_encoding(BINARY)
      end
    end

    # Transcode the passed content from one encoding to another
    #
    # content - a string of content
    # src_enc - the source encoding. this is the encoding +content+ is assumed to be in
    # dst_enc - the encoding to transcode +content+ into
    #
    # Raises: an ArgumentError exception if transcoding failed
    #
    # Returns a String, the transcoded version of +content+
    def transcode(content, src_enc, dst_enc)
      args = { :source => src_enc, :target => dst_enc }
      GitRPC.instrument :charlock_transcode, args do |_|
        CharlockHolmes::Converter.convert content, src_enc, dst_enc
      end
    end
    alias transcode_text transcode

    # Check if a string contains enough data to make a somewhat accurate
    # encoding detection.
    #
    # content - a string to be checked
    #
    # Returns true or false
    def detectable?(content)
      content && content.bytesize >= DETECTABLE_LEN
    end

    def valid_utf8?(content)
      encoding = content.encoding

      content.force_encoding(UTF8).valid_encoding?
    ensure
      content.force_encoding(encoding)
    end

    protected

    def encoding_detector
      Thread.current[:_charlock_detector] ||= CharlockHolmes::EncodingDetector.new
    end

    def lookup(name)
      CharlockHolmes::EncodingDetector.encoding_table[name]
    end
  end
end
