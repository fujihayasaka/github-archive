# frozen_string_literal: true

module HasLabelFiltering
  def include_label_link(label_id)
    label_id = label_id.to_s
    label_ids = label_ids_from_query - ["-#{label_id}"]
    label_ids << label_id

    url_for_label_ids(label_ids)
  end

  def exclude_label_link(label_id)
    label_id = label_id.to_s
    label_ids = label_ids_from_query - [label_id]
    label_ids << "-#{label_id}"

    url_for_label_ids(label_ids)
  end

  def uninclude_label_link(label_id)
    label_id = label_id.to_s
    label_ids = label_ids_from_query - [label_id]

    url_for_label_ids(label_ids)
  end

  def unexclude_label_link(label_id)
    label_id = label_id.to_s
    label_ids = label_ids_from_query - ["-#{label_id}"]

    url_for_label_ids(label_ids)
  end

  private

  def label_ids_from_query
    request.query_parameters["label_ids"]&.split(",") || []
  end

  def url_for_label_ids(label_ids)
    url_for(request.query_parameters.merge(label_ids: label_ids.uniq.join(","), page: nil))
  end
end
