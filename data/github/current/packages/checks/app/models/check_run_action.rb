# typed: true
# frozen_string_literal: true

class CheckRunAction
  include ActiveModel::Validations

  ACTION_LABEL_MAX_LENGTH = 20
  ACTION_IDENTIFIER_MAX_LENGTH = 20
  ACTION_DESCRIPTION_MAX_LENGTH = 40

  validates_length_of :label, maximum: ACTION_LABEL_MAX_LENGTH
  validates_length_of :identifier, maximum: ACTION_IDENTIFIER_MAX_LENGTH
  validates_length_of :description, maximum: ACTION_DESCRIPTION_MAX_LENGTH

  attr_reader :label, :identifier, :description

  def initialize(label, identifier, description)
    @label = label
    @identifier = identifier
    @description = description
  end

  def encode_with(coder)
    coder["label"] = label
    coder["identifier"] = identifier
    coder["description"] = description
  end

  def [](key)
    begin
      self.public_send(key)
    rescue NoMethodError
      nil
    end
  end
end
