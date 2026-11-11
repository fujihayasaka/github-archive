# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class RewriteMannequinAssociationsJob < ApplicationJob
  queue_as :rewrite_mannequin_associations

  RETRYABLE_ERRORS = [
    ActiveRecord::StatementInvalid
  ].freeze

  MAX_ATTEMPTS = 3

  retry_on *RETRYABLE_ERRORS, wait: :polynomially_longer, attempts: MAX_ATTEMPTS do |job, error|
    source = job.arguments.first
    target = job.arguments.second

    GitHub.logger.error("Could not rewrite all associations of source login", {
      exception: error,
      "code.function": "retry_on",
      "code.namespace": "RewriteMannequinAssociationsJob",
      "gh.migration_tools.job.source_id": source.id,
      "gh.migration_tools.job.target_id": target.id,
     }
    )
  end

  retry_on_dirty_exit

  def perform(source, target, invitation)
    context = {
      "code.namespace" => self.class.name,
      "gh.migration_tools.job.source_id" => source.id,
      "gh.migration_tools.job.target_id" => target.id,
      "gh.migration_tools.job.invitation_id" => invitation.id,
    }

    Failbot.push(context) do
      GitHub.logger.info(
        "Starting mannequin association rewrite",
        {
          "code.function": "perform",
          "code.namespace": self.class.name,
          "gh.migration_tools.job.source_id": source.id,
          "gh.migration_tools.job.target_id": target.id,
          "gh.migration_tools.job.invitation_id": invitation.id,
        }
      )

      with_write do
        rewriter = MannequinAssociationRewriter.new(source, target)
        rewriter.rewrite!
        source.claimant = target
        invitation.complete!
      end

      GitHub.logger.info(
        "Rewrote all associations of source login",
        {
          "code.function": "perform",
          "code.namespace": self.class.name,
          "gh.migration_tools.job.source_id": source.id,
          "gh.migration_tools.job.target_id": target.id,
          "gh.migration_tools.job.invitation_id": invitation.id,
        }
      )
    end
  end
end
