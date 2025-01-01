# typed: true
# frozen_string_literal: true

module MemexProjectItem::Content
  extend T::Sig
  extend T::Helpers
  abstract!
  requires_ancestor { Object }

  # Serializes the base attributes of this object for the `content` key of the result of
  # MemexProjectItem#to_hash.
  #
  # The values serialized here should be generic ones that are always required by the client. They
  # should not include values that are specific to a column of the memex; those are handled by
  # `memex_special_type_column_value` in this interface and `MemexProjectItem#generic_type_column_value`.
  # Additionally, the receiver of this method should be a valid `content` association of a
  # MemexProjectItem.
  #
  # Returns a Hash.
  def memex_content_hash(fields: [])
    raise NotImplementedError
  end

  sig { abstract.returns(Elastomer::Interfaces::Document::MemexProjectItem::Content) }
  def memex_content_elasticsearch_document; end

  # Retrieves the value of the given MemexProjectColumn for this object.
  #
  # The receiver of this method should be a valid `content` association of a MemexProjectItem.
  #
  # column - MemexProjectColumn
  # require_prefilled_associations - Whether or not we should raise an exception if we're about to
  #   serialize an association that has not already been prefilled (meaning we're likely to generate
  #   an N+1).
  #
  # Returns an object representing the value for the given column.
  def memex_special_type_column_value(column, require_prefilled_associations:)
    raise NotImplementedError
  end

  # Constructs an object to store as the denormalized value for title on the
  # `memex_project_column_values` table.
  def memex_denormalized_title_value
    raise NotImplementedError
  end

  # Return true if the content for this item can have a milestone
  def can_have_milestone?
    raise NotImplementedError
  end

  # Constructs an object to store as the denormalized value for milestone on the
  # `memex_project_column_values` table.
  def memex_denormalized_milestone_value
    raise NotImplementedError
  end
end
