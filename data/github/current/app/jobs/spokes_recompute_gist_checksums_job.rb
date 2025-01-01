# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: false
# frozen_string_literal: true

require "github/dgit/delegate"
require "github/dgit/error"
require "github/dgit/maintenance"

class SpokesRecomputeGistChecksumsJob < ApplicationJob
  queue_as :dgit_repairs

  locked_by timeout: ActiveJob::LockingJob::DEFAULT_LOCK_TIMEOUT, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  def perform(gist_id)
    Failbot.push spec: "gist/#{gist_id}",
      app: "github-dgit"
    GitHub.logger.with_named_tags("gh.spokes.spec" => "gist/#{gist_id}") do
      GitHub.logger.info("start", "code.function" => "perform!")
      perform!(gist_id)
    end
  rescue Freno::Throttler::Error
  end

  def perform!(gist_id)
    raise ArgumentError, "given nil gist_id" if gist_id.nil?
    gist = Gist.find_by_id(gist_id)
    raise GitHub::DGit::ChecksumInitError, "Gist ID #{gist_id} not found" unless gist

    GitHub::DGit::Maintenance.recompute_gist_checksums(gist, :vote)
  end
end
