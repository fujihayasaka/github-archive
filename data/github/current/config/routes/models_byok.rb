# typed: strict
# frozen_string_literal: true

T.bind(self, ActionDispatch::Routing::Mapper)

scope(
  "/organizations/:organization_id/settings",
  constraints: { organization_id: USERID_REGEX },
  as: :org_settings,
) do
  scope module: :models_byok, as: :byok do
    resources :organization_custom_models, only: [:index, :create, :update], path: "custom-models", as: :custom_models
    put "custom-models", to: "organization_custom_models_batch_updates#update", as: :custom_models_batch_updates
    post "custom-models/:provider/models", to: "organization_provider_models#create",
      as: :custom_models_fetch_provider_models
    resources :organization_custom_keys, only: [:destroy, :update], path: "custom-keys", as: :custom_keys
  end
end
