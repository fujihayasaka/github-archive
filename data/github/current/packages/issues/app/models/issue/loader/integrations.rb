# typed: true
# frozen_string_literal: true

class Issue::Loader::Integrations < Issue::Loader::Base
  def initialize(context, integration_ids: [])
    @context = context
    @integration_ids = integration_ids
  end

  def self.load_for(context, integration_ids: [])
    super new(context, integration_ids: integration_ids)
  end

  def load
    Integration.strict_loading.
      where(id: @integration_ids).
      index_by(&:id).tap do |integrations_by_id|
        @context.preload_attr(:integrations_by_id, integrations_by_id)
      end
  end

  def self.load_for_bots(context, bot_ids: [])
    Integration.strict_loading.
      where(bot_id: bot_ids).tap do |integrations|
        integrations.each do |integration|
          context.integrations_by_id[integration.id] = integration unless context.integrations_by_id[integration.id]
        end
      end
  end

  def self.attach_performed_via_integration(context, models)
    Promise.all(
      models.map do |model|
        next unless model.performed_by_integration_id
        integration = context.integrations_by_id[model.performed_by_integration_id]
        next unless integration
        integration.async_readable_by?(context.viewer).then do |readable|
          if readable
            GitHub::PrefillAssociations.prefill_associations(model, :performed_via_integration, available_records: [integration])
            [model, integration]
          end
        end
      end
    ).then do |models_and_integrations|
      context.preload_attr(:integrations_by_model, models_and_integrations.compact.to_h)
    end.sync
  end

  def self.attach_integrations_to_bots(context, bots)
    context.integrations.each do |integration|
      bot = context.users_by_id[integration.bot_id]
      next unless bot
      GitHub::PrefillAssociations.prefill_associations(bot, :integration, available_records: [integration])
    end
  end
end
