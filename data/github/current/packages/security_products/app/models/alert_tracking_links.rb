# typed: strict
# frozen_string_literal: true

# Helper methods for alert tracking links
module AlertTrackingLinks
  sig { params(entity: T.any(Repository, Organization, Business)).returns(T::Boolean) }
  def self.enabled?(entity)
    if entity.is_a?(Repository)
      entity.feature_flag_enabled?(:code_scanning_alert_tracking_links, memoize: false, default: false) ||
      !!entity.owner&.feature_flag_enabled?(:code_scanning_alert_tracking_links, memoize: false, default: false)
    else
      entity.feature_flag_enabled?(:code_scanning_alert_tracking_links, memoize: false, default: false)
    end
  end

  sig { params(entity: T.any(Repository, Organization, Business)).returns(T::Boolean) }
  def self.phase_2_enabled?(entity)
    enabled?(entity) &&
      if entity.is_a?(Repository)
        entity.feature_flag_enabled?(:code_scanning_alert_tracking_links_phase_2, memoize: false, default: false) ||
        !!entity.owner&.feature_flag_enabled?(:code_scanning_alert_tracking_links_phase_2, memoize: false, default: false)
      else
        entity.feature_flag_enabled?(:code_scanning_alert_tracking_links_phase_2, memoize: false, default: false)
      end
  end
end
