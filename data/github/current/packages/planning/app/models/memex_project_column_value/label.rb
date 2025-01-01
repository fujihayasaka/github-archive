# typed: strict
# frozen_string_literal: true

class MemexProjectColumnValue::Label < T::Struct
  include MemexProjectColumnValue::SerializableValue

  const :id, Integer
  const :name, String
  const :name_html, String
  const :color, String
  const :url, String

  sig { override.returns(MemexProjectColumn::IDataSource::JSONValue) }
  def to_hash
    {
      color: color,
      id: id,
      name: name,
      nameHtml: name_html,
      url: url,
    }
  end

  sig { override.returns(String) }
  def to_s
    name_html
  end

  sig { override.returns(String) }
  def to_csv
    name
  end
end
