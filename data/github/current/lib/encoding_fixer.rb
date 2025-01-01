# typed: true
# frozen_string_literal: true

class EncodingFixer # :nodoc:
  def initialize(options = {})
    @fixed_value   = false
    @invalid_value = false
    @stats_key     = "#{options[:stats_key] || "generic_encoding_fix"}.ascii"
    @raise_error   = options[:raise_error] || false
    @create_needle = options[:create_needle] || false
    @extended_data = options[:extended_data] || nil
  end

  def fix(value)
    value = fix_value value

    if @fixed_value
      GitHub.dogstats.increment(@stats_key, tags: ["action:#{action}", "type:fixe"])
      create_needle("Fixed value of string(s) on #{action}", value) if @create_needle
    end

    if @invalid_value
      GitHub.dogstats.increment(@stats_key, tags: ["action:#{action}", "type:invalid"])
      create_needle("Invalid value of string(s) on #{action}", value) if @create_needle
    end

    value
  end

  def action
    "force_encode"
  end

  private

  class InvalidEncodingError < ArgumentError; end

  def create_needle(msg, value)
    raise InvalidEncodingError, msg
  rescue InvalidEncodingError => e
    GitHub::Logger.log_exception({ error: msg, value: value.inspect, extended_data: @extended_data }, e)
    Failbot.report(e)
  end

  def fix_value(value)
    case value
    when String
      if value.encoding == Encoding::ASCII_8BIT && !value.ascii_only?
        @fixed_value = true

        unless value.frozen?
          # Try making the value utf-8
          value.force_encoding "UTF-8"

          # If it isn't utf-8, log a thing and tag it as binary again
          unless value.valid_encoding?
            begin
              if @raise_error
                raise InvalidEncodingError, "Unable to force encoding of: #{value.inspect}"
              else
                @invalid_value = true
                value.force_encoding Encoding::ASCII_8BIT
              end
            rescue InvalidEncodingError => e
              GitHub::Logger.log_exception({ value: value.inspect, extended_data: @extended_data }, e)
              Failbot.report(e)
              raise e
            end
          end
        end
      end
    when Hash
      value.each_value { |v| fix_value(v) }
    when Array
      value.each { |v| fix_value(v) }
    end

    value
  end

  class Read < EncodingFixer
    def action
      "read"
    end
  end

  class Write < EncodingFixer
    def action
      "write"
    end
  end
end
