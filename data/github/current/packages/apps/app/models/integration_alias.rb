# typed: true
# frozen_string_literal: true

class IntegrationAlias < ApplicationRecord::Collab
  include GitHub::Validations

  belongs_to :integration, required: true

  validates :integration_id, uniqueness: true
  validates :slug, presence: true, unicode3: true
  validates :slug, uniqueness: { case_sensitive: false }, if: -> { T.bind(self, IntegrationAlias).errors[:slug].blank? }
end
