# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProgrammaticAccessBot < Platform::Objects::Base
      # We should never publicly expose these objects
      description "Personal access tokens (V2) bots"

      visibility :internal

      def self.async_api_can_access?(permission, bot)
        false
      end

      def self.async_viewer_can_see?(permission, bot)
        false
      end

      scopeless_tokens_as_minimum

      database_id_field

      implements_node templates: [[:pab, :programmatic_access_bot_id]], as: "PABOT", ready_date: Platform::Helpers::GlobalId::COHORT_5 do |pa_bot|
        { prefix: :pab, programmatic_access_bot_id: pa_bot.id }
      end
    end
  end
end
