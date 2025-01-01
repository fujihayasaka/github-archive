# frozen_string_literal: true

require "yaml"

module NormalYAML
  def self.load(yaml)
    return nil if yaml.nil?

    YAML.safe_load(yaml, permitted_classes: [BigDecimal, Date, Time])
  end

  def self.dump(data)
    return nil if data.nil?

    YAML.dump(normalize(data))
  end

  def self.normalize(data)
    case data
    when Array
      data.map { |element| normalize(element) }
    when Hash
      {}.tap do |normalized|
        data.keys.sort.each do |key|
          unless key.is_a?(String) || key.is_a?(Symbol) || key.is_a?(Integer)
            raise ArgumentError, "NormalYAML requires String, Symbol, or Integer keys."
          end

          new_key =
            case key
            when Symbol then key.to_s
            when /\A\d+\z/ then key.to_i
            else key
            end

          normalized[new_key] = normalize(data[key])
        end
      end
    when TrueClass, FalseClass, NilClass, Integer, Float
      data
    when String
      String.new(data, encoding: "UTF-8")
    when BigDecimal
      BigDecimal(data)
    when Date
      Date.new(data.year, data.month, data.day)
    when Time
      utc = data.utc
      sec_with_frac = utc.sec + utc.subsec
      Time.utc(utc.year, utc.month, utc.day, utc.hour, utc.min, sec_with_frac)
    when ActiveModel::Type::Binary::Data
      data.to_s
    else
      raise ArgumentError,
        "NormalYAML does not support #{data.class.name} serialization."
    end
  rescue StandardError => error
    ::GitHub::Telemetry::Logs.logger.debug { "Failed to normalize this data:\n---\n#{data}\n---" }
    raise error
  end

  def self.normal?(data)
    normalize(data) == data
  rescue StandardError
    false
  end

  def self.valid?(yaml)
    begin
      self.load(yaml)
    rescue StandardError
      false
    end
    true
  end
end
