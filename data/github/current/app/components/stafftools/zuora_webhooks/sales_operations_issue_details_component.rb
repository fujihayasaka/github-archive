# typed: true
# frozen_string_literal: true

class Stafftools::ZuoraWebhooks::SalesOperationsIssueDetailsComponent < ApplicationComponent
  def initialize(webhook:)
    @webhook = webhook
  end

  private

  attr_reader :webhook

  def render?
    webhook.present?
  end
end
