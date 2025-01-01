# typed: false
# frozen_string_literal: true

class WindbeamExport < ApplicationRecord::Domain::Windbeam
  self.table_name = "windbeam_exports"

  belongs_to :user

  enum :state, [:pending, :in_progress, :completed, :failed]

  validates :user, presence: true
  validates :state, presence: true

  scope :newest, -> { order(created_at: :desc) }

  after_initialize :set_default_state, if: :new_record?

  def start_export
    update(state: :in_progress)
  end

  def complete_export
    update(state: :completed)
  end

  def fail_export
    update(state: :failed)
  end

  def set_azure_url(url)
    update(azure_url: url, azure_url_updated_at: Time.current)
  end

  def set_request_id(request_id)
    update(request_id: request_id)
  end

  private

  def set_default_state
    self.state ||= :pending
  end
end
