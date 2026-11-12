# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

class Labelizer
  extend T::Sig

  DEFAULT_DEPENDENCIES_LABEL = "dependencies"
  LIGHT_BLUE = "0366d6"

  sig do
    params(update_config: UpdateConfig, dependencies: T::Array[Dependabot::Dependency]).void
  end
  def initialize(update_config:, dependencies:)
    @update_config = update_config
    @dependencies = dependencies
  end

  sig { returns(T::Array[MonolithTwirp::Dependabot::PullRequests::V1::Label]) }
  def labels
    if update_config.custom_labels.present?
      [
        update_config.custom_labels.map do |label|
          MonolithTwirp::Dependabot::PullRequests::V1::Label.new(name: label, is_custom: true)
        end,
        update_type,
      ].flatten.compact.uniq
    else
      [
        default_label,
        package_manager_labels,
        update_type,
      ].compact.uniq
    end
  end

  private

  sig { returns(UpdateConfig) }
  attr_reader :update_config

  sig { returns(T::Array[Dependabot::Dependency]) }
  attr_reader :dependencies

  sig { returns(MonolithTwirp::Dependabot::PullRequests::V1::Label) }
  def default_label
    MonolithTwirp::Dependabot::PullRequests::V1::Label.new(
      name: DEFAULT_DEPENDENCIES_LABEL,
      color: LIGHT_BLUE,
      description: "Pull requests that update a dependency file",
      is_custom: false,
    )
  end

  sig { returns(T.nilable(MonolithTwirp::Dependabot::PullRequests::V1::Label)) }
  def package_manager_labels
    details = Dependabot::PullRequestCreator::Labeler.label_details_for_package_manager(update_config.package_manager)
    language = details[:name]

    MonolithTwirp::Dependabot::PullRequests::V1::Label.new(
      name: language,
      color: details[:colour],
      description: details.fetch(:description, "Pull requests that update #{language} code"),
      is_custom: false,
    )
  end

  sig { returns(T.nilable(MonolithTwirp::Dependabot::PullRequests::V1::Label)) }
  def update_type
    return unless dependencies.any?(&:previous_version)

    case precision
    when 0 then MonolithTwirp::Dependabot::PullRequests::V1::Label.new(name: "non-semver", is_custom: false)
    when 1 then MonolithTwirp::Dependabot::PullRequests::V1::Label.new(name: "major", is_custom: false)
    when 2 then MonolithTwirp::Dependabot::PullRequests::V1::Label.new(name: "minor", is_custom: false)
    when 3 then MonolithTwirp::Dependabot::PullRequests::V1::Label.new(name: "patch", is_custom: false)
    else nil
    end
  end

  sig { returns(T.nilable(Integer)) }
  def precision # rubocop:disable Metrics/PerceivedComplexity
    dependencies.filter_map do |dep|
      new_version = version(dep)
      next if new_version.nil?

      new_version_parts = new_version.split(/[.+]/)
      old_version_parts = previous_version(dep)&.split(/[.+]/) || []
      all_parts = new_version_parts.first(3) + old_version_parts.first(3)
      # rubocop:disable Performance/RedundantEqualityComparisonBlock
      next 0 unless all_parts.all? { |part| part.to_i.to_s == part }
      # rubocop:enable Performance/RedundantEqualityComparisonBlock
      next 1 if new_version_parts[0] != old_version_parts[0]
      next 2 if new_version_parts[1] != old_version_parts[1]

      3
    end.min
  end

  sig { params(dep: Dependabot::Dependency).returns(T.nilable(String)) }
  def version(dep) # rubocop:disable Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity
    return dep.version if version_class.correct?(dep.version)

    source = dep.requirements.find { |r| r.fetch(:source) }&.fetch(:source)
    type = source&.fetch("type", nil) || source&.fetch(:type, nil)
    return dep.version unless type == "git"

    ref = source.fetch("ref", nil) || source.fetch(:ref, nil)
    version_from_ref = ref&.gsub(/^v/, "")
    return dep.version unless version_from_ref
    return dep.version unless version_class.correct?(version_from_ref)

    version_from_ref
  end

  sig { params(dep: Dependabot::Dependency).returns(T.nilable(String)) }
  def previous_version(dep) # rubocop:disable Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity
    version_str = dep.previous_version
    return version_str if version_class.correct?(version_str)

    source = T.must(dep.previous_requirements).
             find { |r| r.fetch(:source) }&.fetch(:source)
    type = source&.fetch("type", nil) || source&.fetch(:type, nil)
    return version_str unless type == "git"

    ref = source.fetch("ref", nil) || source.fetch(:ref, nil)
    version_from_ref = ref&.gsub(/^v/, "")
    return version_str unless version_from_ref
    return version_str unless version_class.correct?(version_from_ref)

    version_from_ref
  end

  sig { returns(T.class_of(Gem::Version)) }
  def version_class
    Dependabot::Utils.version_class_for_package_manager(update_config.package_manager)
  end
end
