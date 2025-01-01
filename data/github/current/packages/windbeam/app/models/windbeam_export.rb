# typed: false
# frozen_string_literal: true

class WindbeamExport < ApplicationRecord::Domain::Windbeam
  include UrlHelpers

  TOKEN_SCOPE = "WindbeamExport"
  TARGET_PARTICIPANT = "copilot-dsr"

  self.table_name = "windbeam_exports"

  belongs_to :user

  enum :state, [:pending, :in_progress, :completed, :failed]

  validates :user, presence: true
  validates :state, presence: true

  scope :newest, -> { order(created_at: :desc) }

  after_initialize :set_default_state, if: :new_record?

  def completed?
    state.to_sym == :completed
  end

  def start_export
    update(state: :in_progress)
    GitHub.dogstats.increment "windbeam.export.state_change", tags: ["state:in_progress"]
  end

  def complete_export
    update(state: :completed)
    GitHub.dogstats.increment "windbeam.export.state_change", tags: ["state:completed"]
  end

  def fail_export
    update(state: :failed)
    GitHub.dogstats.increment "windbeam.export.state_change", tags: ["state:failed"]
  end

  def set_azure_url(url)
    update(azure_url: url, azure_url_updated_at: Time.current)
    GitHub.dogstats.increment "windbeam.export.azure_url_set"
  end

  def set_request_id(request_id)
    update(request_id: request_id)
  end

  def url_with_token
    user = self.user
    token = user.signed_auth_token(
      scope:   TOKEN_SCOPE,
      expires: created_at + 7.days,
      data:    { export_id: id }
    )

    settings_windbeam_download_path(token: token)
  end

  def self.token_to_url(token_string, current_user)
    token = User.verify_signed_auth_token(
      token: token_string,
      scope: TOKEN_SCOPE
    )
    return unless token.valid?

    export = WindbeamExport.find_by(id: token.data["export_id"])

    return unless export
    return unless export.user_id == token.user.id
    return unless export.user_id == current_user.id
    return unless export.azure_url

    # Refresh the Azure URL if it's older than 12 hours
    if export.azure_url_updated_at < 12.hours.ago
      begin
        client = Dsr.windbeam_client
        request_id = export.request_id
        updated_azure_url = client.get_download_url(request_id, TARGET_PARTICIPANT)

        if updated_azure_url.nil?
          GitHub.dogstats.increment "windbeam.export.azure_url_refresh", tags: ["status:nil"]
          return
        end

        ActiveRecord::Base.connected_to(role: :writing) do
          export.set_azure_url(updated_azure_url)
        end

        GitHub.dogstats.increment "windbeam.export.azure_url_refresh", tags: ["status:success"]
      rescue WindbeamApi::Errors::CommunicationError, Faraday::ConnectionFailed => e
        Failbot.report(e)
        GitHub.dogstats.increment "windbeam.export.azure_url_refresh", tags: ["status:failure"]
        return
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        Failbot.report(e)
        GitHub.dogstats.increment "windbeam.export.azure_url_refresh", tags: ["status:failure_unexpected"]
        return
      end
    end

    export.azure_url
  end

  private

  def set_default_state
    self.state ||= :pending
  end
end
