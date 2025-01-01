# typed: true
# frozen_string_literal: true

require "github-launch"
require "github/launch_client"

module Actions::LargerRunners::DefaultRunnersHelper
  extend T::Sig
  include Actions::LargerRunnersHelper
  include Actions::LargerRunnersControllerHelper
  include Actions::RunnerGroupsHelper

  DEFAULT_RUNNERS_GROUP_NAME = "Default Larger Runners"
  DEFAULT_RUNNERS_BANNER_NOTICE_NAME = "larger_runners_setup_default_dialog_available"

  sig { params(entity: T.any(Organization, Business)).returns(T.nilable(Integer)) }
  def ensure_default_runners_group_exists_and_get_id(entity:)
    runner_groups = Actions::RunnerGroup.for_entity(entity)
    default_larger_runners_group = runner_groups.find { |runner_group| runner_group.name == DEFAULT_RUNNERS_GROUP_NAME }

    return default_larger_runners_group.id if default_larger_runners_group.present?

    result = create_group_for(
      entity,
      name: DEFAULT_RUNNERS_GROUP_NAME,
      visibility: Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_ALL,
      allow_public: false
    )

    if !result.call_succeeded?
      return nil
    end

    result&.value&.runner_group.id
  end

  sig { params(entity: T.any(Organization, Business), group_id: Integer, actor: User).returns(T::Array[T::Boolean]) }
  def create_default_larger_runners(entity:, group_id:, actor:)
    all_runners_created_successfully = T.let(true, T::Boolean)
    at_least_one_runner_created_successfully = T.let(false, T::Boolean)

    default_runners_configurations.each do |runner|
      runner_post_model = Actions::LargerRunner.new(
        name: runner[:name],
        platform: runner[:image].platform,
        runner_group_id: group_id,
        labels: [],
        maximum_runners: runner[:maximum_runners],
        image: Actions::LargerRunner::ImageKey.new(source: runner[:image].source, id: runner[:image].id),
        machine_spec_id: runner[:machine_spec].id,
        is_public_ip_enabled: false,
        image_sas_uri: ""
      )

      result = create_larger_runners_for(entity, larger_runner: runner_post_model, actor: actor)

      if !result.call_succeeded?
        all_runners_created_successfully = false
      else
        at_least_one_runner_created_successfully = true
      end
    end

    [all_runners_created_successfully, at_least_one_runner_created_successfully]
  end

  # We are hard-coding the default runners configurations in dotcom, because "Setup Default Runners" banner can be displayed
  # for customers who are not onboarded to Larger Runners yet (i.e. don't have Host in Runner service).
  # Without Host we can't get the default runners configurations from the Runner service. So it's purely a mock for UI.
  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def default_runners_configurations
    linux_image = {
      image: Actions::Image.new(
        id: "ubuntu-latest",
        display_name: "Ubuntu",
        platform: "linux-x64",
        source: :Curated
      ),
      name: "ubuntu-latest-m",
      machine_spec: Actions::MachineSpec.new(
        id: "4-core",
        cpu_cores: 4,
        memory_gb: 14,
        storage_gb: 150
      ),
      os_version: "22.04",
      maximum_runners: 10,
      price: "$0.016 per minute",
      image_path: "modules/site/enterprise/linux.svg"
    }
    windows_image = {
      image: Actions::Image.new(
        id: "windows-latest",
        display_name: "Windows",
        platform: "win-x64",
        source: :Curated
      ),
      name: "windows-latest-l",
      machine_spec: Actions::MachineSpec.new(
        id: "8-core",
        cpu_cores: 8,
        memory_gb: 32,
        storage_gb: 300
      ),
      os_version: "2022",
      maximum_runners: 10,
      price: "$0.064 per minute",
      image_path: "modules/site/enterprise/windows.svg"
    }

    T.let([linux_image, windows_image], T::Array[T::Hash[Symbol, String]])
  end

  sig { params(entity: T.any(Organization, Business), user: T.nilable(User)).returns(T.nilable(T::Boolean)) }
  def should_display_default_runners_banner?(entity:, user:)
    return false unless GitHub.actions_larger_runners_enabled?

    billing_owner = get_billing_owner_from_entity(entity)
    return false if billing_owner != entity
    return false unless GitHub.flipper[:larger_runners_default_runners_banner].enabled?(billing_owner)
    return false unless entity.can_use_larger_runners? || entity.is_eligible_to_onboard_larger_runners?
    return false if dismissed_notice_for_entity?(entity: entity, user: user)

    true
  end

  sig { params(entity: T.any(Organization, Business), user: T.nilable(User)).returns(T::Boolean) }
  def dismissed_notice_for_entity?(entity:, user:)
    if entity.is_a?(Business)
      T.must(user).dismissed_business_notice?(DEFAULT_RUNNERS_BANNER_NOTICE_NAME, business_id: entity.id) ||
        T.must(user).dismissed_business_notice?(DEFAULT_RUNNERS_BANNER_NOTICE_NAME, business_id: entity.id, for_whole_business: true)
    elsif entity.is_a?(Organization)
      T.must(user).dismissed_organization_notice?(DEFAULT_RUNNERS_BANNER_NOTICE_NAME, entity) ||
        T.must(user).dismissed_organization_notice?(DEFAULT_RUNNERS_BANNER_NOTICE_NAME, entity, for_whole_org: true)
    end
  end
end
