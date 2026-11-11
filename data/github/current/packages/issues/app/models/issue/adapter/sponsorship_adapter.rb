# typed: true
# frozen_string_literal: true

class Issue::Adapter::SponsorshipAdapter < Issue::Adapter::Base
  attr_reader :created_at
  attr_reader :sponsorable

  def initialize(context, sponsorship:, sponsorable:)
    super(context)
    @created_at = sponsorship.created_at
    @sponsorable = sponsorable
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    []
  end
end
