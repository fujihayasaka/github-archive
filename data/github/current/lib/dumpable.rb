# typed: true
# frozen_string_literal: true

# Module for adding ModelIterator-like capabilities to ActiveRecord models.
# This assumes the state is tracked outside GitHub.com (for example: maybe an
# API consumer wants to iterate through all of the public repositories).
#
# TODO: Possibly add this to ModelIterator::Iterable or something.
module Dumpable
  extend T::Helpers

  requires_ancestor { ApplicationRecord::Base }

  class Options
    PAGE_SIZE_DEFAULT = 100
    PAGE_SIZE_MAX = 1000
    PAGE_SIZE_RANGE = 1..PAGE_SIZE_MAX
    ORDER = "ID ASC".freeze

    attr_writer :cursor, :page_size

    def initialize(cursor = nil, page_size = nil, conditions = nil)
      @cursor     = cursor
      @page_size  = page_size
      @conditions = conditions
    end

    def self.from(value)
      case value
      when self then value
      when Hash then fill(value)
      when nil then new
      else
        raise ArgumentError, "unsupported input type: #{value.class}"
      end
    end

    def self.fill(hash)
      new.fill(hash)
    end

    def fill(hash)
      hash.each_pair do |key, value|
        send("#{key}=", value)
      end if hash
      self
    end

    def custom_conditions?
      !Array(raw_conditions).first.empty?
    end

    def page_size
      size = (@page_size || PAGE_SIZE_DEFAULT).to_i
      if !PAGE_SIZE_RANGE.include?(size)
        size = @page_size = PAGE_SIZE_DEFAULT
      end
      size
    end

    def conditions
      @set_custom_conditions ||= begin
        cond = Array(raw_conditions)
        cond[0] += (custom_conditions? ? " AND ID > ?" : "ID > ?")
        cond << cursor
        cond
      end
    end

    def conditions=(value)
      @set_custom_conditions = nil
      @conditions = value
    end

    def raw_conditions
      @conditions ||= [""]
    end

    def cursor
      @cursor ||= 0
    end

    def to_activerecord_options
      { conditions: conditions, limit: page_size, order: ORDER }
    end
  end

  module ClassMethods
    extend T::Helpers

    def dump_page(options = nil)
      options = dumpable_options(Options.from(options))
      T.unsafe(self).where(options[:conditions]).limit(options[:limit]).order(options[:order])
    end

    def dumpable_options(options)
      options.to_activerecord_options
    end
  end

  def self.included(model)
    model.extend ClassMethods
  end

  mixes_in_class_methods(ClassMethods)
end
