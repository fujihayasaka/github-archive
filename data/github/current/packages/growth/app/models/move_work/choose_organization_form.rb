# typed: true
# frozen_string_literal: true

class MoveWork::ChooseOrganizationForm
  include ActiveModel::Model

  attr_accessor :organization_id

  validates :organization_id, presence: true
end
