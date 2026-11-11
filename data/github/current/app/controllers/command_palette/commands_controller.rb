# typed: true
# frozen_string_literal: true

module CommandPalette
  class CommandsController < CommandPaletteController
    include ApplicationController::VerifiedFetchDependency

    before_action :ensure_commands_enabled

    allow_verified_fetch only: [:execute]

    def execute # rubocop:todo GitHub/UseRestfulActions
      context = Context.new(
        current_user: current_user,
        subject: subject,
        scope: scope,
        user_session: user_session,
        cap_filter: cap_filter,
        return_to: return_to
      )

      command = Commands::CommandFinder.find_command(context, params[:command])
      return render_404 if !command

      results = cap_filter.authorized([command.scoped_object])
      return render_404 if results.empty?

      response = command.run

      respond_to do |format|
        format.json do
          render json: {
            action: response.action,
            arguments: response.arguments,
          }
        end
      end
    end

    private

    def ensure_commands_enabled
      return if T.must(current_user).commands_provider_enabled?
      render_404
    end
  end
end
