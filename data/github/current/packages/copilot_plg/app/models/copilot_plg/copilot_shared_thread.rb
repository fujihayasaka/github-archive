# typed: strict
# frozen_string_literal: true

module CopilotPLG
  class CopilotSharedThread < ApplicationRecord::Domain::CopilotPLG
    attr_readonly :slug, :thread_id

    validates :slug, presence: true, uniqueness: true
    validates :thread_id, presence: true, uniqueness: true
    validates :shared_at, presence: true

    before_validation :set_slug, on: :create
    before_validation :set_shared_at, on: :create

    private

    sig { void }
    def set_slug
      self.slug ||= SecureRandom.uuid
    end

    sig { void }
    def set_shared_at
      self.shared_at ||= Time.current
    end
  end
end
