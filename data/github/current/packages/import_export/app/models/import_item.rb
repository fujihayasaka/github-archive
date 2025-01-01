# typed: true
# frozen_string_literal: true

class ImportItem < ApplicationRecord::Domain::Repositories
  include Base64
  include GitHub::Validations

  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain
  belongs_to :user
  has_many :import_errors, class_name: "ImportItemError"

  STATUSES = %w( pending failed imported ).freeze

  validates_inclusion_of :status, in: STATUSES
  validates_presence_of :repository_id, :user_id
  validates :json_data, unicode: true

  def model
    return unless model_type && model_id

    klass = T.must(model_type).camelcase.constantize
    klass.find(model_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  def add_import_error(payload_location:, resource:, field: nil, value: nil, code:)
    import_errors.create do |error|
      error.payload_location = payload_location
      error.resource         = resource
      error.field            = field
      error.value            = value
      error.code             = code
    end
  end

  attribute :json_data, StringFromBinary.new

  def data
    if json_data
      GitHub::JSON.load(json_data)
    end
  end

  def data=(data)
    self.json_data = data && GitHub::JSON.dump(data)
  end
end
