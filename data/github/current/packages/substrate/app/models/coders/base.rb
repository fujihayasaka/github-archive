# typed: strict
# frozen_string_literal: true

# The Coders::Base class is intended to be an inherited class for use
# with the `serialize` column when the Rails provided Hash Coder does
# not meet your needs
class Coders::Base

  class << self
    ###
    # Params: list of symbols that represent the keys of the data
    # Returns: nil
    # Side Effects: Creates instance methods adding a reader, writer, and
    # the `?` method alias to the reader methods. The reader and writer methods
    # delegate to the underlying data hash
    #
    sig { params(iaccessors: Symbol).void }
    def data_accessors(*iaccessors)
      iaccessors.each do |iaccessor|
        define_reader_method(iaccessor)
        define_question_method(iaccessor)
        define_writer_method(iaccessor)
      end
      nil
    end

    ###
    # Returns: collection of public methods the coder responds to
    # as a result of the call to data_accessors
    # This is used to make it easier to delegate calls from the
    # host ActiveRecord object
    #
    sig { returns(T::Array[Symbol]) }
    def members
      @members ||= T.let([], T.nilable(T::Array[Symbol]))
    end

    READER_METHOD_EXCLUDE_PATTERN = T.let(/(\=|\?)\Z/.freeze, Regexp) # Ignore methods ending in "=" or "?".
    ###
    # Note: Method used to filter out reader methods from the
    # class `members` collection
    # Returns: array of symbols representing available reader methods
    #
    sig { returns(T::Array[Symbol]) }
    def reader_members
      members.reject { |member| member.to_s.match?(READER_METHOD_EXCLUDE_PATTERN) }
    end

    private

    ###
    # Note: Private Class Method
    # Side Effects: Creates the reader instance method for the
    # supplied accessor and adds the accessor to the members
    # collections
    #
    sig { params(iaccessor: Symbol).void }
    def define_reader_method(iaccessor)
      members << iaccessor
      define_method(iaccessor) { data["#{iaccessor}".to_sym] }
    end

    ###
    # Note: Private Class Method
    # Side Effects: Creates the `?` alias to the reader of the
    # supplied accessor adding the `?` method name to the members
    # collections
    #
    sig { params(iaccessor: Symbol).void }
    def define_question_method(iaccessor)
      question = "#{iaccessor}?".to_sym
      members << question
      alias_method question, iaccessor
    end

    ###
    # Note: Private Class Method
    # Side Effects: Creates the writer instance method for the
    # supplied accessor and adds the writer method to the members
    # collections
    #
    sig { params(iaccessor: Symbol).void }
    def define_writer_method(iaccessor)
      writer = "#{iaccessor}=".to_sym
      members << writer
      define_method(writer) { |value| data["#{iaccessor}".to_sym] = value }
    end
  end

  ###
  # Params: Hash from the decoding of the data from the DB. This is
  # passed in from the `Coders::Handler.load` call
  # Returns: New instance of the coder subclass
  #
  sig { params(options: T::Hash[T.untyped, T.untyped]).void }
  def initialize(options = {})
    @data = options
  end

  ###
  # Returns: Hash objcect that has been stripped of key value pairs
  # where the value is nil. Used with the `Coders::Handler.dump` call
  #
  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def to_h
    reader_members.reduce({}) do |memo, reader|
      memo[reader] = send(reader)
      memo
    end
      .reject { |_key, value| value.nil? }
  end

  private

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  attr_accessor :data

  ###
  # Note: Private method used to filter out reader methods from the
  # class `members` collection
  # Returns: array of symbols representing available reader methods
  #
  sig { returns(T::Array[Symbol]) }
  def reader_members
    self.class.reader_members
  end

  ###
  # Note: Private Method used as a helper by instances of the subclass
  # Returns: Time
  # Used when casting the string data read in from the `Coders::Handler.load`
  # to a Time object. While in memory if the writer method has been called and
  # updated with a Time object it will not alter the new data
  #
  sig { params(object: T.untyped).returns(T.untyped) }
  def time(object)
    case object
    when String then Time.parse(object)
    else
      object
    end
  end
end
