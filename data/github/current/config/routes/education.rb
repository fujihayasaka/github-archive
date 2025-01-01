# typed: strict
# frozen_string_literal: true

T.bind(self, ActionDispatch::Routing::Mapper)

scope module: :settings do
  resource :settings, only: [] do
    resource :orcid_connection, only: [:new, :show, :destroy]

    resource :education, module: :education, only: [] do
      resource :developer_pack_applications, only: [:show, :create] do
        scope module: :developer_pack_applications do
          resources :schools, only: [:index]
        end
      end
    end
  end
end
