# typed: true
# frozen_string_literal: true

require "charlock_holmes"
require "charlock_holmes/string"
require "active_support/core_ext/string/output_safety"

module GitHub
  # Set of helper methods for dealing with encodings in the app.
  # It would be good of us to reuse this across all of our apps.
  #
  # It will always work toward giving back UTF-8 content
  module Encoding
    extend self
    include Kernel

    UTF8       = "UTF-8"
    VALID_UTF8 = {
      encoding: UTF8,
      ruby_encoding: UTF8,
      confidence: 100,
    }.freeze
    BYTE_ORDER_MARKER = "\uFEFF".freeze

    # Public: LEGACY! Do not use on new models or columns.
    #
    # Declare attributes of an AR model backed by a binary columns to make them
    # act vaguely like a UTF-8 string column.
    #
    # This is a holdover from a time before we could use utf8mb4 columns. Never
    # use this on a string column, only a legacy binary column. When possible
    # just use a utf8mb4 string column instead of this hack.
    #
    # E.g.
    # class MyModel < ActiveRecord::Base
    #   extend GitHub::Encoding
    #
    #   force_utf8_encoding :some_attr, :other_attr, :some_method
    # end
    #
    def force_utf8_encoding(*attrs)
      encoding_module.module_eval do
        T.bind(self, Module)
        Array(attrs).each do |name|
          define_method(name) do
            if value = super()
              if value.respond_to?(:force_encoding) && value.encoding != ::Encoding::UTF_8
                value.force_encoding(UTF8)
              end
              value
            end
          end

          define_method("#{name}_before_type_cast".to_sym) do
            if value = super()
              if value.respond_to?(:force_encoding) && value.encoding != ::Encoding::UTF_8
                value.force_encoding(UTF8)
              end
              value
            end
          end
        end
      end
    end

    # Try to guess the encoding
    #
    # content - a string
    #
    # Returns a Hash, with :encoding, :confidence, :type and optionally :language
    #         this will return nil if an error occurred during detection or
    #         no valid encoding could be found
    def guess(content, context: nil)
      if content.ascii_only?
        VALID_UTF8
      elsif content.encoding == ::Encoding::UTF_8 && content.valid_encoding?
        VALID_UTF8
      else
        GitHub.dogstats.time "encoding", sample_rate: 0.01, tags: ["action:detection"] do
          encoding_detector.detect(content).tap do |detected|
            if context.present?
              encoding = detected.nil? ? "unknown" : "detected"
              tags = ["encoding:#{encoding}", "context:#{context}"]
              GitHub.dogstats.increment("github.encoding.guess", tags: tags)
              exception = StandardError.new("Encoding detection required")
              exception.set_backtrace(caller)
              Failbot.report_trace(exception, method: context, type: encoding)
            end
          end
        end
      end
    end
    alias guess_encoding guess

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
      return content if content.empty?
      GitHub.dogstats.time "encoding", sample_rate: 0.01, tags: ["action:transcode"] do
        begin
          CharlockHolmes::Converter.convert content, src_enc, dst_enc
        rescue ArgumentError
          # We can reach argument error when the source encoding that the user passed is invalid.
          # We don't have a lot of options, that are strictly valid
          begin
            guess = CharlockHolmes::EncodingDetector.detect(content)
            utf8_encoded_content = CharlockHolmes::Converter.convert content, guess[:encoding], dst_enc
          rescue ArgumentError
            # if converting to the specificed encoding failed and our guess failed,
            # treat the commit message as empty
            ""
          end
        end
      end
    end
    alias transcode_text transcode

    # Try to guess the input encoding, then transcode +content+ to UTF-8
    #
    # content - a string
    #
    # Returns a String, the transcoded version of +content+
    #         the unmodified +content+ is returned if the content is already UTF-8
    #         nil is returned if transcoding failed for any reason
    def guess_and_transcode(content, context: nil)
      # Optimistic: most strings will already be in UTF8,
      # so we always force the encoding before hand and check for
      # a valid byte sequence
      content = content.dup if content.frozen?
      original_encoding = content.encoding

      content.force_encoding(::Encoding::UTF_8)
      detected = guess(content, context: context)
      if detected && detected[:encoding] == UTF8
        # We were right! The string was UTF8 all along. Just return the input
        # now that we've set its encoding properly.
        return content
      end

      # The input is not UTF8. Reset its encoding so the caller won't see the
      # string was modified. We're going to allocate a new string with the
      # correct encoding below.
      content.force_encoding(original_encoding)

      return nil if !detected || detected[:type] == :binary

      begin
        transcode(content, detected[:encoding], UTF8)
      rescue ArgumentError => e
        nil
      end
    end
    alias guess_encoding_and_transcode guess_and_transcode

    # We shouldn't even try to guess the encoding if we have
    # less content than this.
    DETECTABLE_LENGTH = 30

    # Try to guess the input encoding, then transcode +content+ to UTF-8.
    # If it can't guess the encoding, it just forces it to be UTF-8.
    #
    # content - a string
    #
    # Returns a String, the transcoded version of +content+
    #         the unmodified +content+ is returned if the content is already
    #         UTF-8 or if transcoding failed for any reason
    def try_guess_and_transcode(content, context: nil)
      return nil if content.nil?

      content = content.dup if content.frozen?
      str = guess_and_transcode(content, context: context) if content&.bytesize >= DETECTABLE_LENGTH
      str = content.force_encoding("UTF-8") if str.nil?
      str.scrub! unless str.html_safe?
      str
    end
    alias try_guess_encoding_and_transcode try_guess_and_transcode

    def strip_bom(string)
      return string unless string.start_with?(BYTE_ORDER_MARKER)
      string.sub(/\A#{BYTE_ORDER_MARKER}/, "")
    end

    protected

    def encoding_detector
      Thread.current[:_charlock_detector] ||= CharlockHolmes::EncodingDetector.new
    end

    def encoding_module
      T.bind(self, Module)
      :GeneratedUTF8EncodingMethods.yield_self do |name|
        const_defined?(name, false) ? const_get(name) : const_set(name, Module.new.tap { |mod| include mod })
      end
    end
  end
end
