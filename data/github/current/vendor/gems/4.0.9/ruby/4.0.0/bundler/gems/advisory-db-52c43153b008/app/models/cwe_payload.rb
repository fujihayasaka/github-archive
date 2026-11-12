# frozen_string_literal: true

class CWEPayload
  include ActiveModel::Validations

  validates :cwe_id, class: String, presence: true
  validates :name, presence: true

  attr_reader :cwe_id

  def initialize(cwe_id)
    @cwe_id = cwe_id
  end

  def name
    return @name if defined? @name

    @name = CWE.find_by(cwe_id: cwe_id)&.name
  end
end
