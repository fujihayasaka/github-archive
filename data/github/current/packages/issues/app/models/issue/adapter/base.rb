# typed: true
# frozen_string_literal: true

class Issue::Adapter::Base
  extend T::Helpers

  extend Scientist

  abstract!

  def initialize(context)
    @context = context
    @invalid = false
  end

  def inspect
    "#<#{self.class}>"
  end

  def is_a?(type)
    if self.class.types.include?(type)
      true
    else
      super(type)
    end
  end

  sig { returns(T.nilable(T::Array[T.anything])) }
  def self.defined_types
    []
  end

  sig { returns(T::Array[T.anything]) }
  def self.types
    return @types if @types

    defined = self.defined_types
    superklass = self.superclass
    supertypes = if superklass && superklass < Issue::Adapter::Base
      superklass.types
    end
    @types = T.must(defined.nil? ? [] : defined) + T.must(supertypes.nil? ? [] : supertypes)
  end

  def raw_object
    raise NotImplementedError
  end

  def invalid?
    @invalid
  end

  def is_pull_request?
    @context.is_a?(PullRequest::Adapter::Context)
  end

  def is_issue?
    @context.is_a?(Issue::Adapter::Context)
  end

  def author_association_symbol(user)
    @author_association_symbol ||= T.unsafe(self).author_association.downcase.to_sym
  end

  protected

  # extracted from app/platform/helpers/url.rb
  # see define_method(path_method_name)
  def resource_path_for(uri)
    return unless uri
    path_uri = uri.dup
    path_uri.scheme = nil
    path_uri.host = nil
    path_uri.port = nil
    path_uri
  end

  attr_reader :context
end
