# typed: strict
# frozen_string_literal: true

module Billing::Usage
  class ActionsUsage
    # Schema
    # {
    #   "MACOS" => Float,
    #   "UBUNTU" => Float,
    #   "WINDOWS" => Float,
    #   "macos_12_core" => Float|NilClass,
    #   "ubuntu_4_core" => Float|NilClass,
    #   "ubuntu_8_core" => Float|NilClass,
    #   "ubuntu_16_core" => Float|NilClass,
    #   "ubuntu_32_core" => Float|NilClass,
    #   "ubuntu_64_core" => Float|NilClass,
    #   "windows_4_core" => Float|NilClass,
    #   "windows_8_core" => Float|NilClass,
    #   "windows_16_core" => Float|NilClass,
    #   "windows_32_core" => Float|NilClass,
    #   "windows_64_core" => Float|NilClass,
    #   "total" => Float
    # }

    VALID_KEYS = T.let(Billing::Actions::RUNNERS + ["total"], T::Array[String])

    VALID_KEYS.map(&:downcase).each do |key|
      T.bind(self, T.class_of(Billing::Usage::ActionsUsage))

      attr_reader key

      private T.unsafe(self).attr_writer key
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    attr_reader :raw_account_usage

    sig { params(raw_account_usage: T::Hash[T.untyped, T.untyped]).void }
    def initialize(raw_account_usage)
      @raw_account_usage = T.let(raw_account_usage.with_indifferent_access.slice(*VALID_KEYS), T::Hash[Symbol, T.untyped])
      @raw_account_usage.each do |key, value|
        self.send("#{key.downcase}=", value)
      end
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def to_h
      @to_h ||= T.let(raw_account_usage.compact, T.nilable(T::Hash[Symbol, T.untyped]))
    end
  end
end
