# typed: strict
# frozen_string_literal: true

##
# MultiReadWriter is a class meant to facilitate dual read/write behaviour
# when removing serialized attributes. It reads from a list of attributes from
# each of the sources in turn, returning the first non-falsey response.
# It writes each of the given attributes to all sources.
class Coders::MultiReadWriter
  extend T::Helpers
  extend T::Sig

  sig { returns(T::Array[T.untyped]) }
  attr_reader :sources

  sig { returns(T::Array[Symbol]) }
  attr_reader :attributes

  sig { params(sources: T::Array[T.untyped], attributes: T::Array[Symbol]).void }
  def initialize(sources:, attributes:)
    @sources = sources
    @attributes = attributes

    define_attribute_methods
  end

  private

  sig { void }
  def define_attribute_methods
    attributes.each do |attribute|
      define_reader_method(attribute)
      define_question_method(attribute)
      define_writer_method(attribute)
    end
  end


  sig { params(attribute: Symbol).void }
  def define_reader_method(attribute)
    self.singleton_class.class_eval do
      define_method(attribute) do
        sources.each do |source|
          val = if source.is_a?(ApplicationRecord::Base)
            source.read_attribute(attribute)
          else
            source.send(attribute)
          end

          return val if val
        end

        nil
      end
    end
  end

  sig { params(attribute: Symbol).void }
  def define_question_method(attribute)
    self.singleton_class.class_eval do
      define_method(:"#{attribute}?") do
        sources.any?(&:"#{attribute}")
      end
    end
  end

  sig { params(attribute: Symbol).void }
  def define_writer_method(attribute)
    self.singleton_class.class_eval do
      define_method(:"#{attribute}=") do |new_value|
        sources.each do |source|
          if source.is_a?(ApplicationRecord::Base)
            next source.write_attribute(attribute, new_value)
          end

          source.send(:"#{attribute}=", new_value)
        end
      end
    end
  end
end
