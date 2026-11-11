# typed: strict
# frozen_string_literal: true

module Configurable
  module ActionsCustomImagesRetentionSettings
    include Instrumentation::Model
    extend T::Helpers
    Error = Class.new(StandardError)

    requires_ancestor { Configurable }

    VERSIONS_PER_IMAGE_LIMIT_KEY = T.let("custom_image_versions_per_image_limit".freeze, String)
    VERSION_MAX_AGE_LIMIT_KEY = T.let("custom_image_version_max_age_limit".freeze, String)
    VERSION_UNUSED_AGE_LIMIT_KEY = T.let("custom_image_version_unused_age_limit".freeze, String)

    VERSIONS_PER_IMAGE_LIMIT_MIN = T.let(1.freeze, Integer)
    VERSION_MAX_AGE_LIMIT_MIN = T.let(7.freeze, Integer)
    VERSION_UNUSED_AGE_LIMIT_MIN = T.let(1.freeze, Integer)

    VERSIONS_PER_IMAGE_LIMIT_MAX = T.let(100.freeze, Integer)
    VERSION_MAX_AGE_LIMIT_MAX = T.let(90.freeze, Integer)
    VERSION_MAX_AGE_LIMIT_MAX_EXCEPTION = T.let(1000.freeze, Integer)
    VERSION_UNUSED_AGE_LIMIT_MAX = T.let(90.freeze, Integer)

    VERSIONS_PER_IMAGE_LIMIT_DEFAULT = T.let(10.freeze, Integer)
    VERSION_MAX_AGE_LIMIT_DEFAULT = T.let(60.freeze, Integer)
    VERSION_UNUSED_AGE_LIMIT_DEFAULT = T.let(30.freeze, Integer)

    # Image versions limit methods
    sig { returns(T.nilable(Integer)) }
    def custom_image_versions_per_image_limit
      value = config.local?(VERSIONS_PER_IMAGE_LIMIT_KEY) ? config.get(VERSIONS_PER_IMAGE_LIMIT_KEY)&.to_i : nil
      value ||= VERSIONS_PER_IMAGE_LIMIT_DEFAULT

      limited_value = [value, max_allowed_custom_image_versions_per_image_limit].min
      [limited_value, VERSIONS_PER_IMAGE_LIMIT_MIN].max
    end

    sig { returns(Integer) }
    def max_allowed_custom_image_versions_per_image_limit
      # custom_image_versions_per_image_limit is bound by configuration owner's value and our hard max
      [owner_versions_per_image_limit, VERSIONS_PER_IMAGE_LIMIT_MAX].min
    end

    sig { params(limit: Integer, actor: ::User).void }
    def set_custom_image_versions_per_image_limit(limit:, actor:)
      validate_limit!(limit, "Image versions per image limit", VERSIONS_PER_IMAGE_LIMIT_MIN, max_allowed_custom_image_versions_per_image_limit)
      config.set(VERSIONS_PER_IMAGE_LIMIT_KEY, limit.to_s, actor)
    end

    # Age limit methods
    sig { returns(Integer) }
    def custom_image_version_max_age_limit
      value = config.local?(VERSION_MAX_AGE_LIMIT_KEY) ? config.get(VERSION_MAX_AGE_LIMIT_KEY)&.to_i : nil
      value ||= VERSION_MAX_AGE_LIMIT_DEFAULT

      limited_value = [value, max_allowed_custom_image_version_max_age_limit].min
      [limited_value, VERSION_MAX_AGE_LIMIT_MIN].max
    end

    sig { returns(Integer) }
    def max_allowed_custom_image_version_max_age_limit
      version_max_age_limit_max = get_version_max_age_limit_max_with_exception
      [owner_version_max_age_limit, version_max_age_limit_max].min
    end

    sig { params(limit: Integer, actor: ::User).void }
    def set_custom_image_version_max_age_limit(limit:, actor:)
      validate_limit!(limit, "Max age limit", VERSION_MAX_AGE_LIMIT_MIN, max_allowed_custom_image_version_max_age_limit)
      config.set(VERSION_MAX_AGE_LIMIT_KEY, limit.to_s, actor)
    end

    # Unused age limit methods
    sig { returns(Integer) }
    def custom_image_version_unused_age_limit
      value = config.local?(VERSION_UNUSED_AGE_LIMIT_KEY) ? config.get(VERSION_UNUSED_AGE_LIMIT_KEY)&.to_i : nil
      value ||= VERSION_UNUSED_AGE_LIMIT_DEFAULT

      limited_value = [value, max_allowed_custom_image_version_unused_age_limit].min
      [limited_value, VERSION_UNUSED_AGE_LIMIT_MIN].max
    end

    sig { returns(Integer) }
    def max_allowed_custom_image_version_unused_age_limit
      [owner_version_unused_age_limit, VERSION_UNUSED_AGE_LIMIT_MAX].min
    end

    sig { params(limit: Integer, actor: ::User).void }
    def set_custom_image_version_unused_age_limit(limit:, actor:)
      validate_limit!(limit, "Unused age limit", VERSION_UNUSED_AGE_LIMIT_MIN, max_allowed_custom_image_version_unused_age_limit)
      config.set(VERSION_UNUSED_AGE_LIMIT_KEY, limit.to_s, actor)
    end

    private

    sig { returns(Integer) }
    def owner_versions_per_image_limit
      configuration_owner&.respond_to?(:custom_image_versions_per_image_limit) ? configuration_owner.custom_image_versions_per_image_limit : VERSIONS_PER_IMAGE_LIMIT_MAX
    end

    sig { returns(Integer) }
    def owner_version_max_age_limit
      if configuration_owner&.respond_to?(:custom_image_version_max_age_limit)
        configuration_owner.custom_image_version_max_age_limit
      else
        get_version_max_age_limit_max_with_exception
      end
    end

    sig { returns(Integer) }
    def owner_version_unused_age_limit
      configuration_owner&.respond_to?(:custom_image_version_unused_age_limit) ? configuration_owner.custom_image_version_unused_age_limit : VERSION_UNUSED_AGE_LIMIT_MAX
    end

    sig { params(limit: Integer, field_name: String, min_value: Integer, max_value: Integer).void }
    def validate_limit!(limit, field_name, min_value, max_value)
      raise Error.new("#{field_name} must be between #{min_value} and #{max_value}.") unless limit.between?(min_value, max_value)
    end

    sig { returns(Integer) }
    def get_version_max_age_limit_max_with_exception
      billing_entity = T.unsafe(self).get_billing_owner_from_entity
      if FeatureFlag.vexi.enabled?(:ims_custom_images_max_age_limit_exception, billing_entity, default: false)
        VERSION_MAX_AGE_LIMIT_MAX_EXCEPTION
      else
        VERSION_MAX_AGE_LIMIT_MAX
      end
    end
  end
end
