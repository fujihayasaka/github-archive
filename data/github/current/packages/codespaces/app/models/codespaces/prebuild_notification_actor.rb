# typed: true
# frozen_string_literal: true

module Codespaces
  class PrebuildNotificationActor < ApplicationRecord::Domain::Codespaces
    self.table_name = "codespace_prebuild_notification_users"
    include Instrumentation::Model

    belongs_to :configuration, class_name: "Codespaces::PrebuildConfiguration", foreign_key: "codespace_prebuild_configuration_id", inverse_of: :actors_to_notify

    validates_presence_of :owner_id
  end
end
