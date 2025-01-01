# typed: true
# frozen_string_literal: true

class KnowledgeBase
  class ContentSource < T::Struct

    const :repository_id, Integer
    const :file_path_filters, T::Array[String]
  end
end
