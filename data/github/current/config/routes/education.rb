# typed: strict
# frozen_string_literal: true

T.bind(self, ActionDispatch::Routing::Mapper)

scope module: :settings do
  resource :settings, only: [] do
    resource :orcid_connection, only: [:new, :show, :destroy]

    resource :education, module: :education, only: [] do
      resources :benefits, only: [:index]

      resource :developer_pack_applications, module: :developer_pack_applications, only: [] do
        resources :schools, only: [:index]
        resources :metadata, only: [:show]
      end

      resources :developer_pack_applications, only: [:new, :create]
    end
  end
end
