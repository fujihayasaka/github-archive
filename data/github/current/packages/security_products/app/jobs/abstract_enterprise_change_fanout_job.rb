# typed: strict
# frozen_string_literal: true

class AbstractEnterpriseChangeFanoutJob < BatchedJob # rubocop:disable GitHub/KubeJobsRetryOnDirtyExit
  extend T::Helpers

  abstract!

  class BusinessNotFoundError < StandardError; end

  BATCH_SIZE = 1000

  before_enqueue do |job|
    business_id = job.arguments.dig(0, :business_id)

    if business_id.nil?
      raise ArgumentError, "Business ID must be provided"
    end
  end

  sig { params(args: T::Array[T.untyped], business_id: T.nilable(Integer), offset_item_id: T.nilable(Integer), kwargs: T.untyped).returns(T::Array[::Integer]) }
  def next_batch(
    *args,
    business_id: nil,
    offset_item_id: nil,
    **kwargs
  )
    business = ::Business.find_by(id: business_id)
    if business.nil?
      raise BusinessNotFoundError, "Business with ID #{business_id} not found"
    end

    business.organizations
      .where(::Organization.arel_table[:id].gt(offset_item_id || 0))
      .limit(BATCH_SIZE)
      .order(:id)
      .pluck(:id)
  end

  sig { params(organization_ids: T::Array[::Integer], args: T.untyped, kwargs: T.untyped).void }
  def process_batch(organization_ids, *args, **kwargs)
    organization_ids.each do |organization_id|
      process_organization(organization_id)
    end
  end

  sig { params(organization_ids: T::Array[::Integer], args: T.untyped, kwargs: T.untyped).returns(T.nilable(Integer)) }
  def next_batch_offset_item_id(organization_ids, *args, **kwargs)
    # Orgs are ordered by ID at query time, so last one will be max
    organization_ids.last
  end

  protected

  sig { params(organization_id: Integer).void }
  def process_organization(organization_id); end

  sig { returns(T::Hash[String, T.untyped]) }
  def logging_context
    super.merge({
      "gh.business.id": arguments.dig(0, :business_id),
      "gh.security_products.source_event": arguments.dig(0, :source_event),
      "gh.security_products.job.offset_item_id": arguments.dig(0, :offset_item_id),
      "gh.security_products.job.initial_start": arguments.dig(0, :initial_start),
      "gh.security_products.job.progress": arguments.dig(0, :progress),
    })
  end

  sig { returns(T::Hash[T.any(String, Symbol), T.untyped]) }
  def failbot_context
    super.merge({
      "gh.business.id": arguments.dig(0, :business_id),
      app: "github-security-center"
    })
  end
end
