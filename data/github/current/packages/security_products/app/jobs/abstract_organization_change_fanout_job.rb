# typed: strict
# frozen_string_literal: true

class AbstractOrganizationChangeFanoutJob < BatchedJob # rubocop:disable GitHub/KubeJobsRetryOnDirtyExit
  extend T::Helpers

  abstract!

  class OrganizationNotFoundError < StandardError; end

  BATCH_SIZE = 1000

  before_enqueue do |job|
    organization_id = job.arguments.dig(0, :organization_id)

    if organization_id.nil?
      raise ArgumentError, "Organization ID must be provided"
    end
  end

  sig { params(args: T.untyped, organization_id: T.nilable(Integer), offset_item_id: T.nilable(Integer), kwargs: T.untyped).returns(T::Array[::Integer]) }
  def next_batch(
    *args,
    organization_id: nil,
    offset_item_id: nil,
    **kwargs
  )
    org = ::Organization.find_by(id: organization_id)
    if org.nil?
      raise OrganizationNotFoundError, "Organization with ID #{organization_id} not found"
    end

    org.repositories
      .where("id > ?", offset_item_id || 0)
      .limit(BATCH_SIZE)
      .order(:id)
      .pluck(:id)
  end

  sig { params(repository_ids: T::Array[::Integer], args: T.untyped, kwargs: T.untyped).void }
  def process_batch(repository_ids, *args, **kwargs)
    repository_ids.each do |repository_id|
      process_repository(repository_id)
    end
  end

  sig { params(repository_ids: T::Array[::Integer], args: T.untyped, kwargs: T.untyped).returns(T.nilable(Integer)) }
  def next_batch_offset_item_id(repository_ids, *args, **kwargs)
    # Repos are ordered by ID at query time, so last one will be max
    repository_ids.last
  end

  protected

  sig { params(repository_id: Integer).void }
  def process_repository(repository_id); end

  sig { returns(T.untyped) }
  def logging_context
    super.merge({
      "gh.org.id": arguments.dig(0, :organization_id),
      "gh.security_products.source_event": arguments.dig(0, :source_event),
      "gh.security_products.job.offset_item_id": arguments.dig(0, :offset_item_id),
      "gh.security_products.job.initial_start": arguments.dig(0, :initial_start),
      "gh.security_products.job.progress": arguments.dig(0, :progress),
    })
  end

  sig { returns(T.untyped) }
  def failbot_context
    super.merge({
      "gh.org.id": arguments.dig(0, :organization_id),
      app: "github-security-center"
    })
  end
end
