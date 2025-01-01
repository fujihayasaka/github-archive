# typed: true
# frozen_string_literal: true

class Issue::Adapter::UserContentEditAdapter < Issue::Adapter::Base
  attr_reader :edited_at
  attr_reader :editor

  def initialize(context, user_content_edit:)
    super(context)

    @edited_at = user_content_edit.edited_at
    @editor = user_content_edit.editor
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    []
  end
end
