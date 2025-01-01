# typed: true
# frozen_string_literal: true

class SpamDatasourceEntry < ApplicationRecord::Domain::Spam
  include GitHub::Validations
  belongs_to :spam_datasource

  validates_presence_of :spam_datasource
  validates_presence_of :value
  validates :value, unicode3: true

  # `additional_context` varchar(255) DEFAULT NULL,
end
