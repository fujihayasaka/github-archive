# frozen_string_literal: true

class ChatopsController < ApplicationController
  skip_forgery_protection

  include ::Chatops::Controller

  NAMESPACE = "ghsa"

  def self.valid_sources
    "Valid sources are: #{AdvisoryDB.sources.map { |s| "`#{s}`" }.to_sentence}"
  end

  # rubocop:disable Rails/LexicallyScopedActionFilter
  before_action :validate_source, only: [:import, :lock, :unlock]
  # rubocop:enable Rails/LexicallyScopedActionFilter

  chatops_namespace NAMESPACE
  chatops_help <<~HELP
    Interact with Advisory DB: import security feeds, see stats, etc.
  HELP

  chatop(
    :import,
    /import\s+(?<source>\S+)/,
    <<~HELP,
      *import <source>*
      Refresh Advisory DB's copy of a security feed's data. #{valid_sources}

    HELP
  ) do
    if ApplicationImporter.locked?(source)
      jsonrpc_failure <<~MSG
        :lock: Sorry, #{source.humanize} import is locked!
        You can `.#{NAMESPACE} unlock #{source}` if you're _sure_ that no #{source.humanize} import is running.
      MSG
    else
      ImportJob
        .set(queue: :high)
        .perform_later(source)

      jsonrpc_success ":ok_hand: #{source.humanize} import coming right up!"
    end
  end

  chatop(
    :import_cve,
    /import\s+cve\s+(?<cve_id>CVE-\d+-\d+)/,
    <<~HELP,
      *import cve <cve id>*
      Import a single CVE ID

    HELP
  ) do
    cve_id = jsonrpc_params[:cve_id]
    ImportJob
      .set(queue: :high)
      .perform_later(NVDImporter.source, cve_id: cve_id)

    jsonrpc_success ":ok_hand: Importing #{cve_id}!"
  end

  chatop(
    :import_friends_of_php,
    /import\s+friends_of_php\s+(?<advisory_path>.+\.yaml)/,
    <<~HELP,
      *import friends_of_php <advisory file path>*
      Import a single record from Friends Of PHP

    HELP
  ) do
    advisory_path = jsonrpc_params[:advisory_path]
    ImportJob
      .set(queue: :high)
      .perform_later(FriendsOfPHPImporter.source, specific_advisory_path: advisory_path)

    jsonrpc_success ":ok_hand: Importing #{advisory_path}!"
  end

  chatop(
    :import_go,
    /import\s+go\s+(?<advisory_path>.+\.yaml)/,
    <<~HELP,
      *import Go <advisory file path>*
      Import a single record from the Go Vulnerability Database

    HELP
  ) do
    advisory_path = jsonrpc_params[:advisory_path]
    ImportJob
      .set(queue: :high)
      .perform_later(GoImporter.source, specific_advisory_path: advisory_path)

    jsonrpc_success ":ok_hand: Importing #{advisory_path}!"
  end

  chatop(
    :import_rubysec,
    /import\s+rubysec\s+(?<advisory_path>.+\.ya?ml)/,
    <<~HELP,
      *import rubysec <advisory file path>*
      Import a single record from Rubysec
    HELP
  ) do
    advisory_path = jsonrpc_params[:advisory_path]
    ImportJob
      .set(queue: :high)
      .perform_later(
        RubysecImporter.source,
        specific_advisory_path: advisory_path,
      )

    jsonrpc_success ":ok_hand: Importing #{advisory_path}!"
  end

  chatop(
    :import_rustsec,
    /import\s+rustsec\s+(?<advisory_path>.+\.md)/,
    <<~HELP,
      *import rustsec <advisory file path>*
      Import a single record from Rustsec
    HELP
  ) do
    advisory_path = jsonrpc_params[:advisory_path]
    ImportJob
      .set(queue: :high)
      .perform_later(
        RustsecImporter.source,
        specific_advisory_path: advisory_path,
      )

    jsonrpc_success ":ok_hand: Importing #{advisory_path}!"
  end

  chatop(
    :import_pysec,
    /import\s+pypa\s+(?<advisory_path>.+\.yaml)/,
    <<~HELP,
      *import pypa <advisory file path>*
      Import a single record from the pypa advisory database
      ex. import pypa vulns/django/PYSEC-2019-11.yaml
    HELP
  ) do
    advisory_path = jsonrpc_params[:advisory_path]
    ImportJob
      .set(queue: :high)
      .perform_later(
        PypaAdvisoryImporter.source,
        specific_advisory_path: advisory_path,
      )
    jsonrpc_success ":ok_hand: Importing #{advisory_path}!"
  end

  chatop(
    :lock,
    /lock\s+(?<source>\S+)/,
    <<~HELP,
      *lock <source>*
      Lock a security feed for import. #{valid_sources}

    HELP
  ) do
    if ApplicationImporter.locked?(source)
      jsonrpc_success ":lock: #{source.humanize} import is already locked!"
    else
      ApplicationImporter.lock(source)
      jsonrpc_success ":lock: Okay, #{source.humanize} import is locked!"
    end
  end

  chatop(
    :unlock,
    /unlock\s+(?<source>\S+)/,
    <<~HELP,
      *unlock <source>*
      Unlock a security feed for import. #{valid_sources}

    HELP
  ) do
    if ApplicationImporter.unlocked?(source)
      jsonrpc_success ":unlock: #{source.humanize} import is already unlocked!"
    else
      ApplicationImporter.unlock(source)
      jsonrpc_success ":unlock: Okay, #{source.humanize} import is unlocked!"
    end
  end

  chatop(
    :merge_advisory_reviews,
    /merge\s+(?<from_ghsa_id>GHSA-\S+)\s+into\s+(?<to_ghsa_id>GHSA-\S+)\s*/,
    <<~HELP,
      *merge <from ghsa_id> into <to ghsa_id>*
      Move the feed entries and identifiers from an open Advisory Review, into Advisory Review B
    HELP
  ) do
    from_ghsa_id = jsonrpc_params[:from_ghsa_id]
    to_ghsa_id = jsonrpc_params[:to_ghsa_id]

    AdvisoryReviewMerger.merge_overlapping_advisory_reviews(
      from_ghsa_id,
      to_ghsa_id,
    )
    jsonrpc_success(":broom: Successfully merged #{from_ghsa_id} into #{to_ghsa_id} :merge:")
  rescue StandardError => error
    jsonrpc_failure(":warning: Failed to merge advisory reviews: #{error}")
  end

  chatop(
    :hydro_publish,
    /hydro\s+publish\s+(?<ghsa_id>GHSA-[a-z\d]{4}-[a-z\d]{4}-[a-z\d]{4})/,
    <<~HELP,
      *hydro publish <ghsa id>*
      Enqueues the `PublishAdvisoryToHydroJob` with an advisory matching the input GHSA id

    HELP
  ) do
    ghsa_id = jsonrpc_params[:ghsa_id]
    advisory = Advisory.find_by(ghsa_id: ghsa_id)
    return jsonrpc_failure ":warning: Advisory not found." if advisory.nil?

    begin
      result = PublishAdvisoryToHydroJob.perform_now(advisory)
      if result.success?
        jsonrpc_success ":rocket: {Published} #{ghsa_id}!"
      else
        jsonrpc_failure ":warning: Failed to publish the advisory."
      end
    rescue StandardError => error
      GitHub::Telemetry::Logs.logger.error(
        "There was an error running the hydro_primary_hydro_executor",
        exception: error,
      )
      jsonrpc_failure ":warning: An error occurred while publishing the advisory: #{error.message}"
    end
  end

  private

  def source
    jsonrpc_params[:source]
  end

  def validate_source
    return if AdvisoryDB.source?(source)

    jsonrpc_failure <<~MSG
      :warning: Sorry, I don't recognize that source!
      #{self.class.valid_sources}
    MSG
  end

  def current_user_login
    params[:user]
  end
end
