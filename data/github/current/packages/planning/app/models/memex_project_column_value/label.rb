# typed: strict
# frozen_string_literal: true

class MemexProjectColumnValue::Label < T::Struct
  const :id, Integer
  const :name, String
  const :name_html, String
  const :color, String
  const :url, String

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def to_hash
    {
      color: color,
      id: id,
      name: name,
      nameHtml: name_html,
      url: url,
    }
  end

  sig { returns(String) }
  def to_csv
    name
  end
end
