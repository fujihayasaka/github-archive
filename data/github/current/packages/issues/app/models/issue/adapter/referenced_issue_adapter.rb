# typed: true
# frozen_string_literal: true

class Issue::Adapter::ReferencedIssueAdapter < Issue::Adapter::Base
  TYPES = [
    PlatformTypes::Issue,
  ].freeze

  attr_reader :state

  def initialize(context, issue:)
    super(context)

    @state = issue.state.to_s.upcase
    @repository_adapter = context.repository_adapter
  end

  def repository
    @repository_adapter
  end

  def state_open?
    @state == "OPEN"
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    TYPES
  end
end
