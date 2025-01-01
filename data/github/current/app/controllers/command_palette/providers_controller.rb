# typed: true
# frozen_string_literal: true

module CommandPalette
  class ProvidersController < CommandPaletteController
    before_action :set_provider_name_for_instrumentation, only: :index

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Collab,
      ApplicationRecord::Repositories,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Configurations,
      ApplicationRecord::Memex,
      ApplicationRecord::Iam,
      only: [:index]

    def index
      context = Context.new(
        current_user: current_user,
        subject: subject,
        scope: scope,
        user_session: user_session,
        cap_filter: cap_filter,
        return_to: return_to
      )

      provider = Providers::Factory.build(params["provider"].to_sym, context)
      return render_404 unless provider.present?

      results = provider.search(query).reject(&:nil?)
      filtered_results = provider.filter_results(results)
      octicons = octicons_svgs(filtered_results)

      respond_to do |format|
        format.json do
          render json: {
            results: filtered_results,
            octicons: octicons
          }
        end
      end
    end

    private

    def octicons_svgs(results)
      results
        .select do |result|
          result.respond_to?(:icon) && result.icon.present? && result.icon.type == :octicon
        end
        .map { |result| result.icon }
        .uniq { |octicon| octicon.id }
        .map do |octicon|
          {
            id: octicon.id,
            svg: octicon.icon
          }
        end
    end

    def set_provider_name_for_instrumentation
      provider = params["provider"]
      return unless Providers::Factory::PROVIDERS.keys.include?(provider.to_sym)

      env[GitHub::TaggingHelper::COMMAND_PALETTE_PROVIDER_NAME_KEY] = provider
    end
  end
end
