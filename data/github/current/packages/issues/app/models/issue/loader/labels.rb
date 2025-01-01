# typed: true
# frozen_string_literal: true

class Issue::Loader::Labels < Issue::Loader::Base
  def initialize(context, label_ids: [])
    @context = context
    @label_ids = label_ids
  end

  def self.load_for(context, label_ids: [])
    super new(context, label_ids: label_ids)
  end

  def load
    labels_by_id = Label.strict_loading.
      where(id: @label_ids).
      index_by(&:id)

    models = labels_by_id.values

    promises = [
      async_preload_attribute(models, :preloaded_name_html, :async_name_html)
    ]

    Promise.all(promises).sync

    labels_by_id
  end
end
