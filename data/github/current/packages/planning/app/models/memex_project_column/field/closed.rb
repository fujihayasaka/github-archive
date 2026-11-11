# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::Closed < MemexProjectColumn::Field::Base
  include Interface::SpecialTypeSerializable
  include Helper::SystemDateField

  sig { override.returns(T::Array[MemexProjectItem::ContentType]) }
  def self.supported_content_types
    [
      MemexProjectItem::ContentType::Issue,
      MemexProjectItem::ContentType::PullRequest,
    ]
  end

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    []
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::Date.new
  end

  sig { override.params(item: MemexProjectItem).returns(T.nilable(ActiveSupport::TimeWithZone)) }
  def content_timestamp(item)
    content_type = MemexProjectItem::ContentType.deserialize(item.content_type)

    case content_type
    when MemexProjectItem::ContentType::Issue,
        MemexProjectItem::ContentType::PullRequest
      item.issue_closed_at
    when MemexProjectItem::ContentType::DraftIssue,
        MemexProjectItem::ContentType::AgentTask
      nil
    else
      T.absurd(content_type)
    end
  end
end
