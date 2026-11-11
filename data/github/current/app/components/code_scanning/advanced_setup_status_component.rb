# typed: strict
# frozen_string_literal: true

class CodeScanning::AdvancedSetupStatusComponent < ApplicationComponent
  include ApplicationComponent::Rescuable

  rescue_from ActiveRecord::ActiveRecordError, with: :nothing

  sig { params(repository: Repository, tools: T::Enumerable[Turboscan::Proto::ToolStatus], advanced_setup_requested: T::Boolean).void }
  def initialize(repository:, tools:, advanced_setup_requested:)
    @repository = repository
    @tools = tools
    @advanced_setup_requested = advanced_setup_requested
  end

  sig { returns(T::Boolean) }
  def render?
    return false unless @repository.security_configuration&.code_scanning_enabled?
    return false unless @advanced_setup_requested
    return false if @tools.any? { |tool| tool.name == "CodeQL" && tool.categories.any? { |category| [:DELIVERY_ORIGIN_YML, :DELIVERY_ORIGIN_API].include?(category.configuration_group&.delivery_origin) } }
    true
  end

  sig { returns(String) }
  def call
    render(GitHub::FlashActionDismissibleComponent.new(
       level: :warning,
       is_dismissible: false,
       test_selector: "advanced-setup-not-working-banner",
       text_align: :left,
       display_icon: true,
       my: 1
     )) do |flash|
      flash.with_title do
        "CodeQL is not working."
      end
      flash.with_text do
        "CodeQL advanced setup has been requested but no analysis has been uploaded for the default branch. Ensure the tool is configured correctly."
      end
    end
  end
end
