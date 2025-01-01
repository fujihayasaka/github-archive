# typed: true
# frozen_string_literal: true

T.bind(self, ActionDispatch::Routing::Mapper)

unless GitHub.enterprise?
  get "/spark/apps", to: "spark/dashboard#show", as: :spark_dashboard
end
