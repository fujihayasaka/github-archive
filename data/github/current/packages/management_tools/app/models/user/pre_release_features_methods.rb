# typed: true
# frozen_string_literal: true

class User
  module PreReleaseFeaturesMethods
    def new_prerelease_features?
      return false if GitHub.enterprise?

      GitHub.dogstats.distribution_time("feature_preview.new_prerelease_features.latency") do
        available_prerelease_features.unseen_by(self).published.any?
      end
    end

    def unseen_prerelease_features
      return [] if GitHub.enterprise?

      GitHub.dogstats.distribution_time("feature_preview.unseen_features_check.latency") do
        available_prerelease_features.unseen_by(self)
      end
    end

    def prerelease_feature_enrollments
      enrollments = available_prerelease_features.reduce({})  do |h, feature|
        h[feature.id] = { enabled: feature.enrolled_by_default? }
        h
      end

      FeatureEnrollment.for_enrollee(self).each do |enrollment|
        next unless enrollments[enrollment.feature_id]

        enrollments[enrollment.feature_id][:opted_out] = enrollment.unenrolled?
        enrollments[enrollment.feature_id][:enabled] = enrollment.enrolled?
      end

      enrollments
    end

    def available_prerelease_features
      @available_prerelease_features ||= Feature.flipper_enabled_for(self)
    end

    def enable_edge_feature(feature)
      result = case feature
      when Feature
        feature.enroll(self)
      else
        Feature.find_by(slug: feature)&.enroll(self)
      end

      return false unless result

      result
    end

    def disable_edge_feature(feature)
      result = case feature
      when Feature
        feature.unenroll(self)
      else
        Feature.find_by(slug: feature)&.unenroll(self)
      end

      return false unless result

      result
    end
  end
end
