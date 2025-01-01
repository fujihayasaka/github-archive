# typed: strict
# frozen_string_literal: true

# Represents a text value in a project column, typically used for
# storing formatted text that may require HTML rendering.
class MemexProjectColumnValue::Text < T::Struct
  include GitHub::Memoizer
  include MemexProjectColumnValue::SerializableValue

  const :value, String, default: ""

  sig { override.returns(MemexProjectColumn::IDataSource::JSONValue) }
  def to_hash
    {
      raw: value,
      html: to_html
    }
  end

  sig { override.returns(String) }
  def to_s
    value
  end

  sig { override.returns(String) }
  def to_csv
    value
  end

  private

  sig { returns(String) }
  memoize def to_html
    GitHub::Goomba::MemexTextColumnPipeline.to_html(value)
  end
end
