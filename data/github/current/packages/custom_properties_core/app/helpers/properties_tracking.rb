# typed: strict
# frozen_string_literal: true

module PropertiesTracking
  extend T::Helpers

  requires_ancestor { CustomPropertiesCore::DomainAccessorBase }

  # Track performance of custom properties operations.
  sig do
    type_parameters(:T).params(
      operation: String,
      tags: T.nilable(T::Hash[T.any(String, Symbol), String]),
      blk: T.proc.returns(T.type_parameter(:T))
    ).returns(T.type_parameter(:T))
  end
  def track(operation, tags: nil, &blk)
    tags = {
      **tags,
      operation:,
      domain: tracking_domain_name,
    }.filter_map { |k, v| "#{k}:#{v}" if v.present? }

    # Pin the host tag to a constant value to reduce cardinality and cost of metric.
    # Also, manually add the current site tag since this was previously
    # auto-added based on the host tag.
    # See https://github.com/github/monolith-fitness/issues/240
    tags.push(GitHub::Dogstats::DEFAULT_HOST_TAG, GitHub::TaggingHelper.site_tag)

    GitHub.dogstats.distribution_time("custom_properties_core.dist", tags:) do
      blk.call
    end
  end

  private

  # Results in something like "repositories.domain.custom_properties"
  sig { returns(String) }
  def tracking_domain_name
    self.class.name.underscore.tr("/", ".")
  end
end
