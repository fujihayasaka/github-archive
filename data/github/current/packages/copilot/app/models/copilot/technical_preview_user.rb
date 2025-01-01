# typed: strict
# frozen_string_literal: true

module Copilot
  class TechnicalPreviewUser < ApplicationRecord::Copilot
    include ::Instrumentation::Model

    self.table_name = "copilot_tech_preview_users"
    self.strict_loading_by_default = true

    belongs_to :user, class_name: "::User", strict_loading: false

    validates :user, presence: true

    scope :unsubscribed, -> { where(subscribed: false) }
    scope :emails_sent, ->(count) { where("sent_email_count = ?", count) }

    sig { returns(T::Class[T.anything]) }
    def sorbet_class
      self.class
    end

    sig { void }
    def subscribe
      update_attribute(:subscribed, true)
    end
  end
end
