# typed: strict
# frozen_string_literal: true

class MemexProjectColumnValue::OptionEntry < T::Struct
  include MemexProjectColumnValue::SerializableValue

  const :id, T.any(String, Integer)
  const :name, T.nilable(String)
  const :name_html, T.nilable(String)
  const :color, T.nilable(String)
  const :description, T.nilable(String)
  const :description_html, T.nilable(String)

  sig { override.returns(T::Hash[T.untyped, T.untyped]) }
  def to_hash
    {
      id: id,
      name: name,
      name_html: name_html,
      color: color,
      description: description,
      description_html: description_html,
    }.compact.with_indifferent_access
  end

  sig { override.returns(String) }
  def to_s
    name.to_s
  end

  sig { override.returns(String) }
  def to_csv
    name.to_s
  end
end
