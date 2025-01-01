# typed: true
# frozen_string_literal: true

module Stafftools::SecurityConfigurationsHelper
  include ActionView::Helpers

  sig do
    params(
      configurations: T::Array[SecurityConfiguration],
      defaults: T::Array[SecurityConfigurationDefault],
      type: Symbol,
      is_a_business: T::Boolean
    ).returns(String)
  end
  def link_to_default_configuration(configurations, defaults, type, is_a_business)
    visibility_column_name = type == :public ? :default_for_new_public_repos : :default_for_new_private_repos
    default = defaults.find { |cd| cd.send(visibility_column_name) == true } # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
    return "Not set" unless default.present?

    config = configurations.find { |sc| sc.id == default.security_configuration_id }
    return "" unless config.present?

    if is_a_business
      link_to config.name,
      security_configuration_stafftools_enterprise_path(security_configuration_id: config.id)
    elsif config.target_type != "global" && config.target.is_a?(Business)
      link_to config.name,
      security_configuration_stafftools_enterprise_path(security_configuration_id: config.id, slug: config.target.slug)
    else
      link_to config.name,
        security_configuration_stafftools_user_path(security_configuration_id: config.id)
    end
  end
end
