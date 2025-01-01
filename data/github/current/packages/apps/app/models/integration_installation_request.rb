# typed: true
# frozen_string_literal: true

# IntegrationInstallationRequest is the request by a User to the owners of an Organization to install a given
# Integration in one or all current / future Repositories in the organization. Ultimately, the owners of the
# Organization decide whether to install or to dismiss the request.
class IntegrationInstallationRequest < ApplicationRecord::Domain::Integrations
  ALL_REPOS = []

  include Instrumentation::Model


  belongs_to :requester, class_name: "User"
  belongs_to :integration
  belongs_to :target, class_name: "User"
  has_many :repository_requests, class_name: "IntegrationInstallationRequestRepository", dependent: :destroy
  has_many :repositories, through: :repository_requests, source: :repository, disable_joins: true

  after_create_commit :instrument_request_created
  after_commit :send_mail_to_target_admins, on: :create

  validates_presence_of :requester, :integration, :target

  validate :target_is_an_organization

  scope :most_recent, -> { order("integration_installation_requests.id DESC") }

  attr_accessor :ephemeral

  def self.ephemeral(integration:, target:, repositories:)
    new(
      integration:  integration,
      target:       target,
      repositories: repositories,
      ephemeral:    true,
    )
  end

  # Mark this request as closed.
  #
  # reason: the reason this request is being closed. Either:
  #         canceled, rejected, approved
  # actor:  the user closing the request (the requester or an admin)
  #
  # Returns result Bool if successfully closed.
  def close(reason:, actor:)
    repo_ids = repositories.ids

    destroy

    if destroyed?
      instrument :close, actor: actor, actor_id: actor.id, reason: reason, repository_ids: repo_ids
    end

    destroyed?
  end

  # Public: indicates if the issuer of the request wants the Integration to be installed in all current and future
  # repositories of the target Organization.
  #
  # Returns boolean
  def request_all_repositories?
    repositories.empty? && T.must(integration).repository_installation_required?(target)
  end

  # Public: indicates if the issuer of the request wants the Integration to be installed in a set of Repositories
  #
  # Returns boolean
  def request_some_repositories?
    !repositories.empty?
  end

  # Public: indicates if the issuer of the request wants the Integration to be installed in no repository of
  # the target Organization. This can only happen if the integration has no repository permissions.
  #
  # Returns boolean
  def request_no_repositories?
    repositories.empty? && !T.must(integration).repository_installation_required?(target)
  end

  def ephemeral?
    !!@ephemeral
  end

  private

  def instrument_request_created
    instrument :create
  end

  def event_payload
    {
      installation_request_id: id,
      requester: requester,
      integration: integration,
      target: target,
      repository_ids: repositories.ids,
    }.tap do |payload|
      payload[T.must(target).event_prefix] = target
    end
  end

  def target_is_an_organization
    unless target&.organization?
      errors.add(:target, "Must be an Organization")
    end
  end

  def send_mail_to_target_admins
    IntegrationMailer.integration_installation_request(self).deliver_later
  end
end
