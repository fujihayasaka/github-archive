# typed: true
# frozen_string_literal: true

class Issue::Loader::CrossReferences < Issue::Loader::Base
  def initialize(context, cross_reference_ids: [])
    @context = context
    @cross_reference_ids = cross_reference_ids
  end

  def self.load_for(context, cross_reference_ids: [])
    super new(context, cross_reference_ids: cross_reference_ids)
  end

  def load
    return {} unless @cross_reference_ids.any?

    CrossReference.
      strict_loading.
      where(id: @cross_reference_ids).
      index_by(&:id)
  end
end
