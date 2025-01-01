module Zuorest::Action
  def create_action(body, headers = {})
    post("/v1/action/create", body:, headers:, url_template: "/v1/action/create")
  end

  def update_action(body, headers = {})
    post("/v1/action/update", body:, headers:, url_template: "/v1/action/update")
  end

  def query_action(body, headers = {})
    post("/v1/action/query", body:, headers:, url_template: "/v1/action/query")
  end
end
