# typed: true
# frozen_string_literal: true

module Stafftools::SecurityConfigurationsHelper
  extend T::Sig
  include ActionView::Helpers

  sig do
    params(
      configurations: T::Array[SecurityConfiguration],
      defaults: T::Array[SecurityConfigurationDefault],
      type: Symbol
    ).returns(String)
  end
  def link_to_default_configuration(configurations, defaults, type)
    visibility_column_name = type == :public ? :default_for_new_public_repos : :default_for_new_private_repos
    default = defaults.find { |cd| cd.send(visibility_column_name) == true } # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
    return "Not set" unless default.present?

    config = configurations.find { |sc| sc.id == default.security_configuration_id }
    return "" unless config.present?

    link_to config.name,
      security_configuration_stafftools_user_path(security_configuration_id: config.id)
  end
end
